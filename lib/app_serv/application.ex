defmodule Serv.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      # Starts a worker by calling: Serv.Worker.start_link(arg)
      # {Serv.Worker, arg},
      {Task.Supervisor, name: Serv.TaskSupervisor},
      Supervisor.child_spec(
        {Task,
         fn ->
           Serv.accept(4040)
           Memo.start()
         end},
        restart: :permanent
      )
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Serv.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
