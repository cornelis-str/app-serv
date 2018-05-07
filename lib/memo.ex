defmodule Memo do
  require Logger
  # TODO: Skriv upp meddelande-syntax för alla operationer som memo_mux ska
  # kunna godkänna.

  # TODO: vänner ska ha bilder? - senare problem. Börja med quests med bilder.
  # Memos interna struktur

  @moduledoc """
  Föräldramodulen för serverns minnsestruktur.
  Detta är modulen som håller koll på alla data_handlers
  vilka är de som håller den faktiska informationen.

  Innehåller främst memo_mux vilken skickar vidare
  meddelanden dit de ska.

  Innehåller även funktioner för att spara data till
  disk. (Ej implemeterat än)
  """

  @doc """
  Startar memo_mux och registrerar processen för enkel sändning av meddelanden.
  """
  def start() do
    {:ok, pid} = Task.Supervisor.start_child(Serv.TaskSupervisor, fn -> memo_mux(%{}, %{}) end)
    Process.register(pid, :memo_mux)

    #spawn(fn -> file_mux(file_path) end) |> Process.register(:file_mux)
  end

  defp memo_mux(user_pid_list, room_pid_list) do
    IO.inspect user_pid_list, label: "user_pid_list"
    IO.inspect room_pid_list, label: "room_pid_list"
    receive do
      {:user, user_id, {:create_user, user_data}} ->
        create_user(user_id, user_data, user_pid_list)
        |> memo_mux room_pid_list

      {:user, user_id, action = {method, _, _}} ->
        case user_pid_list[user_id] do

          nil ->
            IO.inspect method, label: "No #{user_id} in user_pid_list (╯ರ ~ ರ）╯︵ ┻━┻"

          pid ->
            Logger.info ":user #{user_id} #{method}"
            #IO.inspect method
            send pid, action
            memo_mux user_pid_list, room_pid_list
        end

      {:room, room_id, action = {method, _, _}} ->
        case room_pid_list[room_id] do

          nil ->
            new_room_pid_list = create_room(room_id, room_pid_list)
            IO.inspect new_room_pid_list, label: "new_room_pid_list"
            send new_room_pid_list[room_id], action
            memo_mux user_pid_list, new_room_pid_list

          room_pid ->
            send room_pid, action
            memo_mux user_pid_list, room_pid_list
        end

      {:quit} ->
        quit(user_pid_list, room_pid_list)
        Logger.info "memo_mux: Bye"

      catch_all ->
        IO.inspect catch_all, [limit: :infinity, label: "Memo_mux catch_all"]
        memo_mux(user_pid_list, room_pid_list)
    end
  end

  def create_user(id, user_data, pid_list) do
    pid_list |> Map.put(id, spawn fn -> Memo_user.data_handler(user_data) end)
  end

  def create_room(id, pid_list) do
    [owner_name, room_name] = id |> String.split("@")

    new_room = %{
      :owner => owner_name,
      :name => room_name,
      :topic => nil,
      :icon => nil,
      :users => [],
      :quests => [],
      :quest_pics => []
    }

    send :memo_mux, {:user, owner_name, {:set, self(), {:room, id, :add}}}

    pid_list |> Map.put(id, spawn(fn -> Memo_room.data_handler(new_room) end))
  end

  def quit(user_pid_list, room_pid_list) do
    # skicka :save och :quit till alla user_data_handler processer
    # ska finnas ett sätt att automatiskt stänga av alla processer i
    # rätt ordning med Tasksupervisor på något sätt...
    save_exit = fn([h|t], f) ->
      case h do
        {_, pid} ->
          #send pid, {:save, user_id}
          send pid, {:quit}
          f.(t,f)
      end
    end

    save_exit.(user_pid_list |> Map.to_list(), save_exit)
    save_exit.(room_pid_list |> Map.to_list(), save_exit)

    # TODO gå inte vidare för än alla barnprocesser är döda
    #send :ld, {:quit}
    #send :file_mux, {:quit}
  end

  ### FILE SAVE AND LOAD ###
  # TODO gör klar
  # Sparar till och laddar från fil
  def file_mux(file_path) do
    file_path |> Path.expand() |> File.stream!([], :line)
    receive do
      {:save, {user_id, user_data}} ->
        "tbd"
        # TODO save to file
      {:load, user_id} ->
        "tbd"
        # TODO load from file
      {:quit} -> :ok
    end
  end

  # TODO ladda user från minnet med file_mux
  def load_user(user_id) do end
end
