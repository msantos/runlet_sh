-module(runlet_task).

%% API exports
-export([
    start_link/2,
    insn/1
]).

%%====================================================================
%% API functions
%%====================================================================
-spec start_link(prx:task(), proplists:proplist()) -> {ok, prx:task()} | {error, prx:posix()}.
start_link(Task, Options) ->
    true = prx:call(Task, setopt, [signaloneof, 9]),
    Init = fun(Parent) ->
        prx:clone(Parent, [
            clone_newipc,
            clone_newns,
            clone_newpid,
            clone_newuts
        ])
    end,

    Terminate = fun(Parent, Child) ->
        Session = prx:pidof(Child) * -1,
        prx:stop(Child),
        prx:kill(Parent, Session, sigkill)
    end,

    Insn = insn(Options),

    prx:task(Task, Insn, [], [{init, Init}, {terminate, Terminate}]).

-spec insn(proplists:proplist()) -> [prx_task:op() | [prx_task:op()]].
insn(Options) ->
    Id = proplists:get_value(uid, Options, erlang:phash2(self(), 16#ffff) + 16#f0000000),

    {ok, Cwd} = file:get_cwd(),

    Root = filename:absname_join(
        Cwd,
        proplists:get_value(
            root,
            Options,
            "priv/root"
        )
    ),
    Opt = filename:absname_join(
        Cwd,
        proplists:get_value(
            opt,
            Options,
            "priv/opt"
        )
    ),

    Fstab = proplists:get_value(fstab, Options, []),

    Prefix = proplists:get_value(host_prefix, Options, "r"),

    [
        {setsid, []},
        {sethostname, [lists:concat([Prefix, Id])]},
        {setpriority, [
            proplists:get_value(which, Options, prio_process),
            proplists:get_value(who, Options, 0),
            proplists:get_value(prio, Options, 19)
        ]},

        {mount, ["none", "/", <<>>, [ms_rec, ms_private], <<>>]},

        % pivot_root(2) requires `new_root` to be a mount point. Bind
        % mount the root directory over itself to create a mount point.
        {mount, [Root, Root, <<>>, [ms_bind], <<>>]},
        {prx, mount,
            [
                Root,
                Root,
                <<>>,
                [
                    ms_remount,
                    ms_bind,
                    ms_rdonly,
                    ms_nosuid
                ],
                <<>>
            ],
            [{errexit, false}]},

        [
            [
                {mount, [Dir, [Root, Dir], "", [ms_bind], <<>>]},
                {mount, [
                    Dir,
                    [Root, Dir],
                    "",
                    [
                        ms_remount,
                        ms_bind,
                        ms_rdonly
                        % ms_nosuid
                    ],
                    <<>>
                ]}
            ]
         || Dir <- [
                "/bin",
                "/sbin",
                "/usr",
                "/lib"
            ]
        ],

        [
            [
                {prx, mount, [Dir, [Root, Dir], "", [ms_bind], <<>>], [{errexit, false}]},
                {prx, mount,
                    [
                        Dir,
                        [Root, Dir],
                        "",
                        [
                            ms_remount,
                            ms_bind,
                            ms_rdonly
                        ],
                        <<>>
                    ],
                    [{errexit, false}]}
            ]
         || Dir <-
                [
                    "/lib64"
                ] ++ Fstab
        ],

        {prx, mount, [Opt, [Root, "/opt"], "", [ms_bind], <<>>], [{errexit, false}]},
        {prx, mount,
            [
                Opt,
                [Root, "/opt"],
                "",
                [
                    ms_remount,
                    ms_bind,
                    ms_rdonly,
                    ms_nosuid
                ],
                <<>>
            ],
            [{errexit, false}]},

        {mount, [
            "tmpfs",
            [Root, "/tmp"],
            "tmpfs",
            [
                ms_noexec,
                ms_nodev,
                ms_noatime,
                ms_nosuid
            ],
            [<<"mode=1777,size=4M">>]
        ]},

        {mount, [
            "tmpfs",
            [Root, "/home"],
            "tmpfs",
            [
                ms_noexec,
                ms_nodev,
                ms_noatime,
                ms_nosuid
            ],
            [
                <<"uid=">>,
                integer_to_binary(Id),
                <<",gid=">>,
                integer_to_binary(Id),
                <<",mode=700,size=8M">>
            ]
        ]},

        % proc on /proc type proc (rw,noexec,nosuid,nodev)
        {mount, [
            "proc",
            [Root, "/proc"],
            "proc",
            [
                ms_noexec,
                ms_nosuid,
                ms_nodev
            ],
            <<>>
        ]},

        {chdir, [Root]},
        {pivot_root, [".", "."]},
        {umount2, [".", [mnt_detach]]},
        {chdir, ["/"]},

        [
            {setrlimit, [Resource, Rlim]}
         || {Resource, Rlim} <- proplists:get_value(
                rlimit,
                Options,
                [
                    {rlimit_core, #{cur => 0, max => 0}},
                    {rlimit_cpu, #{cur => 120, max => 150}},
                    {rlimit_fsize, #{cur => 4194304, max => 4194304}},
                    {rlimit_nofile, #{cur => 128, max => 128}},
                    {rlimit_nproc, #{cur => 16, max => 16}}
                ]
            )
        ],
        {setgroups, [[]]},
        {setresgid, [Id, Id, Id]},
        {setresuid, [Id, Id, Id]}
    ].

%%====================================================================
%% Internal functions
%%====================================================================
