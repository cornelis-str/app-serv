defmodule Memo do
  require Logger

  def start(file_path) do
    # Ta bort kommentering i lib/application.ex för att det ska fungera
    {:ok, pid} = Task.Supervisor.start_child(Memo.TaskSupervisor, fn -> memo_mux() end)

    handler_generator(file_path)
    |> memo_mux()
  end

  def memo_mux(pid_list) do
    recieve do
      {id, action} ->
        case pid_list[id] do
          # Hur sköter elixir maps? Kommer nedan tillägg att finnas i alla
          # versioner av mapen? referens eller kopia?
          nil -> 
            pid_list[id] = spawn fn -> 
              create_user(id) 
              |> user_data_handler() 
            end
            |> send action # Funkar det här? pipea pid från ovan...
          pid -> send pid, action
        end
    end
    memo_mux pid_list
  end

  # Hämtar och ändrar user data på begäran.
  def user_data_handler(user_data) do
    receive do
      {:get, thing} -> user_data[thing]
      {:set, thing, value} -> user_data[thing] = value
      {:save} -> :ok # TODO skickar user_data till funktion som skriver ner till fil
      {:quit} -> :quit
    end
    user_data_handler(user_data)
  end

  # TODO
  # Läser från fil/minnet, startar processer och populerar handler_pids
  def handler_generator(file_path) do end

  # TODO
  # Tar imot data och skriver den till fil(/databas?). 
  # Bör hålla koll på skriven data för att hinda duplicering?
  def user_data_saver(file_path) do end
end
