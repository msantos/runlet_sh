defmodule RunletSh.Mixfile do
  use Mix.Project

  def project do
    [
      app: :runlet_sh,
      version: "1.2.3",
      elixir: "~> 1.9",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: "Generate runlets from containerized Unix processes",
      deps: deps(),
      package: package(),
      dialyzer: [
        list_unused_filters: true,
        flags: [
          "-Wunmatched_returns",
          :error_handling,
          :race_conditions,
          :underspecs
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
      {:alcove, "~> 0.36.0"},
      {:prx, "~> 0.14.1"},
      {:runlet, github: "msantos/runlet"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false}
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
