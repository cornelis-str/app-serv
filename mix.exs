defmodule Serv.MixProject do
  use Mix.Project

  def project do
    [
      app: :app_serv,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Docs
      name: "Server",
      source_url: "https://gits-15.sys.kth.se/anee/app_serv",
      homepage_url: "https://gitgnome.github.io",
      docs: [
        main: "Server",
        extras: ["README.md"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Serv.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
      {:jason, "~> 1.0"},
      {:earmark, "~> 1.2.5", only: :dev},
      {:ex_doc, "~> 0.16", only: :dev, runtime: false}
    ]
  end
end
