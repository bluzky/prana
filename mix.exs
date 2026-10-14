defmodule Prana.MixProject do
  use Mix.Project

  def project do
    [
      app: :prana,
      version: "0.2.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: description(),
      package: package(),
      source_url: "https://github.com/bluzky/prana",
      docs: docs()
    ]
  end

  defp description do
    "Elixir workflow automation library built around a node-based graph execution model " <>
      "with port-based routing, conditional branching, and sub-workflow support."
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "docs/guides/writing_integrations.md",
        "docs/guides/building_workflows.md",
        "docs/guides/wait_resume_integration_guide.md",
        "docs/built-in-integrations.md",
        "docs/integrations/manual.md",
        "docs/integrations/logic.md",
        "docs/integrations/data.md",
        "docs/integrations/workflow.md",
        "docs/integrations/wait.md",
        "docs/integrations/http.md",
        "docs/integrations/code.md"
      ],
      groups_for_extras: [
        Guides: ~r/docs\/guides\/.*/,
        Integrations: ["docs/built-in-integrations.md", ~r/docs\/integrations\/.*/]
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/bluzky/prana"},
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:mau, "~> 0.7"},
      {:nestex, "~> 0.2"},
      {:req, "~> 0.5"},
      {:skema, "~> 1.4"},
      {:elixir_uuid, "~> 1.2"},
      {:styler, "~> 1.5", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.3", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}

      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
