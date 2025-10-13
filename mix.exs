defmodule RunletSh.Mixfile do
  use Mix.Project

  def project do
    [
      app: :runlet_sh,
      version: "1.2.8",
      elixir: "~> 1.9",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: "Generate runlets from containerized Unix processes",
      deps: deps(),
      package: package(),
      dialyzer: [
        list_unused_filters: true,
        flags: [
          :unmatched_returns,
          :error_handling,
          :underspecs
        ]
      ]
    ]
  end

  defp deps do
    [
      {:alcove, "~> 1.0.0"},
      {:prx, "~> 1.0.0"},
      {:runlet, "~> 1.2"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.1", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:gradient, github: "esl/gradient", only: [:dev], runtime: false}
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
