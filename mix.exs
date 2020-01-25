defmodule RunletSh.Mixfile do
  use Mix.Project

  def project do
    [
      app: :runlet_sh,
      version: "1.1.0",
      elixir: "~> 1.9",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: "Generate runlets from containerized Unix processes",
      deps: deps(),
      package: package(),
      dialyzer: [
        plt_add_deps: :transitive,
        ignore_warnings: "dialyzer.ignore-warnings",
        paths: [
          "_build/dev/lib/prx/ebin",
          "_build/dev/lib/runlet/ebin"
        ]
      ]
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  # def application do
  #  [applications: [:logger]]
  # end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:prx, "~> 0.10.0"},
      {:runlet, "~> 1.0", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Michael Santos"],
      licenses: ["ISC"],
      links: %{github: "https://github.com/msantos/runlet_sh"}
    ]
  end
end
