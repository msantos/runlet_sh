defmodule RunletSh.Mixfile do
  use Mix.Project

  @version "1.2.9"

  def project do
    [
      app: :runlet_sh,
      version: @version,
      elixir: "~> 1.9",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      description: "Generate runlets from containerized Unix processes",
      dialyzer: [
        list_unused_filters: true,
        flags: [
          :unmatched_returns,
          :error_handling,
          :underspecs
        ]
      ],
      name: "runlet_sh",
      source_url: "https://github.com/msantos/runlet_sh",
      homepage_url: "https://github.com/msantos/runlet_sh"
    ]
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      extras: [
        "README.md": [title: "Overview"]
      ],
      main: "readme"
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
