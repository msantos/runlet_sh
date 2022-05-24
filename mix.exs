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

  defp deps do
    [
      {:alcove, "~> 0.38.0"},
      {:prx, "~> 0.14.1"},
      {:runlet, github: "msantos/runlet"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.1", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.28", only: :dev, runtime: false}
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
