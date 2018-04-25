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
          {:notifs, notif} ->
            set_notif user_data, notif, value, pid
            |> user_data_handler
          {:friends, userID} ->
            set_friend user_data, userID, value, pid
            |> user_data_handler
          {:rooms, roomID, roomPart} ->
            set_room user_data, roomID, roomPart, value, pid
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

  def get_notif(map, req, val, pid) do

  end

  def get_friend(map, req, val, pid) do end
  def get_room(map, req, val, pid) do end
  def get_quest(map, req, val, pid) do end
  def get_quest_pics(map, req, val, pid) do end

  def set_notif(map, notif, method, pid) do
    case method do
      :del -> map.notifs |> List.delete(notif)
      :add ->
        map.notifs
        |> Enum.member?(notif)
        |> case do
          true -> send pid, {:memo, :ok}
          false ->
            map |> Map.replace!(:notifs, [notif | map.notifs])
            send pid, {:memo, :ok}
          end
    end
  end

# :friends => [{:friend, {:userID => id, :friends => []}}, etc...],
  def set_friend(map, userID, friend, pid) do
    # hitta friend i listan
    # tabort friend
    # lägg till friend
    # annars endast lägg till friends
    map.friends
    |> Enum.find_index(friend)
    |> case do
      nil ->
        map
        |> Map.replace!(:friends, [friend | map.friends])
      index ->
        map
        |> Map.replace!(:friends, [friend | map.friends |> List.delete_at(index)])
    end
  end

# :rooms => [%{:roomId => roomID, :room => room}, etc...]
# room = {
# :owner => "Kor-Nelzizs",
# :name => "Super Duper Room",
# :topic => "Underground Brony Cabal",
# :icon => <<ByteArray>>
# :users => [{:user, userID}, etc...]
# :quests => [{:quest, {:resID, resID, :json, <JsonString>}}]
# :quest_pics => [{:quest_pic, {:resID, resID, :pic, <<ByteArray>>}}]
# }
  def set_room(map, roomID, roomPart, part, pid) do
    # get room
    # find part
    # replace part
    # replace old room in room list
    map.rooms
    |> Enum.find(fn(%{:roomID => x, _}) -> x == roomID end)
    |> case do
      nil -> map |> Map.replace!(:rooms, [part | map.rooms])
      %{_, :room => room} ->
        case roomPart do
          :room -> map |> Map.replace!(:rooms, [part | map.rooms |> ])
          :owner ->
          :name ->
          :topic ->
          :icon ->
          :users ->
          _ -> send pid, {:memo, "Use correct function"}
        end
    end
  end

  def set_quest(map, questID, quest, pid) do end
  def set_quest_pics(map, pic_ID, pic, pid) do end

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
