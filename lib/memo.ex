defmodule Memo do
  require Logger

  # user_data = {
  # :userID => lolcat,
  # :notifs => [{:friendReq, {:from, lolcat, :to, doggo}}, {:roomInv, {:room, [], :to, lolcat}}, etc...],
  # :friends => [{:friend, {:userID => id, :friends => []}}, etc...],
  # :rooms => {:room, {}}, {:room, {}}, etc...},
  # :hasNew => false,
  # }
  # room = {
  # :name => "Super Duper Room",
  # :topic => "",
  # :icon => <<ByteArray>>
  # :users => [{:user, userID}, etc...]
  # :quests => [{:quest, {:resID, resID, :json, <JsonString>}}]
  # :quest_pics => [{:quest_pic, {:resID, resID, :pic, <<ByteArray>>}}]
  # }
  # Hämtar och ändrar user data på begäran.

  def start(file_path) do
    # Ta bort kommentering i lib/application.ex för att det ska fungera
    {:ok, _} = Task.Supervisor.start_child(Memo.TaskSupervisor, fn -> memo_mux([]) end)
    spawn(fn -> file_mux(file_path) end) |> Process.register(:fmux)
  end

  def memo_mux(pid_list) do
    receive do
      {:msg, {id, action}} ->
        case pid_list[id] do
          nil ->
            # Vad är scopet för pid_list här? Är denna pid_list samma som i
            # memo_mux pid_list nedan?
            pid_list |> Map.put(id, spawn fn -> create_user(id) |> user_data_handler() end)
            send pid_list[id], action
          pid -> send pid, action
        end
        memo_mux pid_list
      {:quit} ->
          # skicka :save och :quit till alla user_data_handler processer
          save_exit = fn([h|t], f) ->
            case h do
              {id, pid} ->
                send pid, {:save, id}
                send pid, {:quit}
                f.(t,f)
              end
          end
          save_exit.(pid_list |> Map.to_list(), save_exit)

          # TODO gå inte vidare för än alla barnprocesser är döda
          send :ld, {:quit}
          send :fmux, {:quit}
    end
  end

  def user_data_handler(user_data) do
    receive do
      {:get, pid, thing} -> send pid, {:memo, user_data[thing]}
      {:set, pid, thing, value} ->
        case thing do
          {:userID} -> user_data |> Map.put(:userID, value)
          {:notifs, request} ->
            set_notif user_data, request, value, pid
            |> user_data_handler
          {:friends, userID} ->
            set_friend user_data, userID, value, pid
            |> user_data_handler
          {:rooms, roomID} ->
            set_room user_data, roomID, value, pid
          {:has_new} ->
            user_data
            |> Map.replace!(:has_new, value)
            |> user_data_handler()
        end

        send pid, {:memo, :ok}
      {:save, id} -> send :fmux, {:save, {id, user_data}}
      {:quit} -> :ok
    end
  end

  def get_notif(data, req, val, pid) do
    case val do
      0 -> List.delete(data.notifs, req)
      _ ->
        Enum.member?(data.notifs, val)
        |> case do
          true -> send pid, {:memo, :ok}
          false ->
            data
            |> Map.replace!(:notifs, [val | data.notifs])
            send pid, {:memo, :ok}
          end
    end
  end
  
  def get_friend do end
  def get_room do end
  def get_quest do end
  def get_quest_pics do end

  def set_notif(map, req, val, pid) do end
  def set_friend(map, req, val, pid) do end
  def set_room(map, req, val, pid) do end
  def set_quest(map, req, val, pid) do end
  def set_quest_pics(map, req, val, pid) do end

  # Sparar till och laddar från fil
  def file_mux(file_path) do
    file_path |> Path.expand() |> File.stream!([], :line)
    receive do
      {:save, {id, user_data}} ->
        "tbd"
        # TODO save to file
      {:load, id} ->
        "tbd"
        # TODO load from file
      {:quit} -> :ok
    end
  end

  # TODO
  # Skapar ny user
  def create_user(id) do

   end
end
