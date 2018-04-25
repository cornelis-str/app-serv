defmodule Memo do
  require Logger

  # user_data = %{
  # :userID => lolcat,
  # :notifs => [%{:friendReq => %{:from => lolcat, :to => doggo}}, %{:roomInv => %{:room => [], :to => lolcat}}, etc...],
  # :friends => [{:friend, %{:userID => id, :friends => []}}, etc...],
  # :rooms => [%{:roomID => roomID, :room => room}, etc...],
  # :hasNew => false | true
  # }
  # room = %{
  # :owner => "Amandaaaaaa"
  # :name => "Super Duper Room",
  # :topic => "",
  # :icon => <<ByteArray>>
  # :users => [{:user, userID}, etc...]
  # :quests => [%{:questID => questID, :quest => <JsonString>}]
  # :quest_pics => [%{:quest_picID => quest_picID, :pic => <<ByteArray>>}]
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
      {:get, pid, thing} ->
        case thing do
          {:userID} -> send pid, user_data.userID
          {:notifs} -> send pid, user_data.notifs
          {:friends, userID} ->
            get_friend user_data, userID, pid
          {:rooms, roomID} ->
            get_room user_data, roomID, pid
          {:quest, questID} ->
            get_quest user_data, questID, pid
          {:quest_pic, resID} ->
            get_quest_pics user_data, resID, pid
          {:has_new} ->
            send pid, user_data.has_new
        end
        user_data_handler(user_data)
      {:set, pid, action, value} ->
        case action do
          {:userID} -> user_data |> Map.put(:userID, value)
          {:notifs, notif, what} ->
            set_notif user_data, what, notif, value, pid

          {:friends, userID, what} ->
            set_friend user_data, what, userID, value, pid

          {:rooms, roomID, roomPart, what} ->
            set_room user_data, what, roomID, roomPart, value, pid

          {:quest, questID, what} ->
            set_quest user_data, what, questID, value, pid

          {:quest_pic, resID, what} ->
            set_quest_pics user_data, what, resID, value, pid

          {:has_new} ->
            user_data
            |> Map.replace!(:has_new, value)

        end
        |> user_data_handler()              # IT WORKS MTFKER!!!

      {:save, id} -> send :fmux, {:save, {id, user_data}}
      {:quit} -> :ok
    end
  end

  def get_friend(map, userID, pid) do
    friend = (map.friends |> Enum.find(fn({:friend, %{:userID => x, :friends => _}}) -> x == userID end))
    send pid, friend
  end

  def get_room(map, roomID, pid) do
    room = (map.rooms |> Enum.find(fn(%{:roomID => x, :room => _}) -> x == roomID end))
    send pid, room
  end

  def get_quest(map, resID, pid) do
    [username, roomname, questname] = String.split(resID, "@")
    room = (map.rooms |> Enum.find(fn(%{:roomID => x, :room => _}) -> x == "#{username}@#{roomname}" end))
    quest = (room.quests |> Enum.find(fn(%{:questID => x, :quest => _}) -> x == resID end))
    send pid, quest
  end

 def get_quest_pics(map, resID, pid) do
    [username, roomname, questname, missionPart, thingName] = String.split(resID, "@")
<<<<<<< HEAD
    room = (map.rooms |> Enum.find(fn(%{:roomID => x, _}) -> x == "#{username}@#{roomname}" end))
    quest_pic = (room.quest_pics |> Enum.find(fn(%{:quest_picID => x, :pic => _}) -> x == resID end))
    send pid, quest_picID
=======
    room = (map.rooms |> Enum.find(fn(%{:roomID => x, :room => _}) -> x == "#{username}@#{roomname}" end))
    quest_pic = (room.quest_pics |> Enum.find(fn({:quest_pic, {:resID, resID2, _, _}}) -> resID2 == resID end))
    send pid, quest_pic
>>>>>>> fe1f29df55421f5c0672adef6bb70a41e0af008f
  end

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
  def set_friend(map, method, userID, friend, pid) do
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
        case method do
          :add ->
            map
            |> Map.replace!(:friends, [map.friends])
          :del ->
            map
            |> Map.replace!(:friends, [friend | map.friends |> List.delete_at(index)]) 
        end
    end
  end

  # :rooms => [%{:roomId => roomID, :room => room}, etc...]
  # room = {
  # :owner => "Kor-Nelzizs",
  # :name => "Super Duper Room",
  # :topic => "Underground Brony Cabal",
  # :icon => <<ByteArray>>
  # :users => [{:user, userID}, etc...]
  # :quests => [%{:questID => questID, :quest => <JsonString>}]
  # :quest_pics => [%{:quest_picID => quest_picID, :pic => <<ByteArray>>}]
  # }
  def set_room(map, method, roomID, roomPart, part, pid) do
    # get room
    # find part
    # replace part
    # replace old room in room list
    map.rooms
    |> Enum.find(fn(%{:roomID => x, :room => _}) -> x == roomID end)
    |> case do
      nil -> map |> Map.replace!(:rooms, [part | map.rooms])
      %{:roomID => _, :room => room} ->
        case roomPart do
          :room when method == :add ->
            map |> Map.replace!(:rooms, [part | map.rooms
            |> Enum.find(fn(%{:roomID => ^roomID, :room => _}) -> true end)
            |> List.delete()])

          :room when method == :del ->
            map |> Map.replace!(:rooms,
            map.rooms
            |> Enum.find(fn (%{:roomID => ^roomID, :room => _}) -> true end)
            |> List.delete() )

          :owner ->
            map |> Map.replace!(:owner, part)

          :name ->
            map |> Map.replace!(:name, part)

          :topic ->
            map |> Map.replace!(:topic, part)

          :icon ->
            map |> Map.replace!(:icon, part)

          :users when method == :add ->
            map.users
            |> Enum.find_index(fn(^part) -> true end)
            |> case do
              nil ->
                map |> Map.replace!(:users, [part | map.users])
              index ->
                map |> Map.replace!(:users, [part |
                map.users
                |> List.delete_at(index)])
            end

          :users when method == :del ->
            map |> Map.replace!(:users,
            map.users
            |> List.delete_at(map.users
            |> Enum.find_index(fn(^part) -> true end)))

          _ -> send pid, {:memo, "SYNTAX ERROR"}
        end
    end
  end


  def set_quest(map, action, questID, quest, pid) do
    [username, roomname, questname] = String.split(resID, "@")
    room = (map.rooms |> Enum.find(fn(%{:roomID => x, :room => _}) -> x == "#{username}@#{roomname}" end))
    case action do
      :del ->
        room.quests |> Enum.find_index(fn(%{:questID => id, :quest => _}) -> id == questID end)
        |> case do
          nil->
            "error handling"
          index ->
            upd_quests = room.quests |> List.delete_at(index)
            upd_room = map.rooms |> Map.replace!(:quests, upd_quests)
            upd_rooms = map.rooms |> Map.replace!(:quest, upd_room)
            upd_map = map |> Map.replace!(:rooms, upd_rooms)
        end
      :add ->
        room.quests |> Enum.find_index(fn(%{:questID => id, :quest => _}) -> id == questID end)
        |> case do
          nil ->
            #Lägg till
            upd_quests = [quest | room.quests]
            upd_room = map.rooms |> Map.replace!(:quests, upd_quests)
            upd_rooms = map.rooms |> Map.replace!(:quest, upd_room)
            upd_map = map |> Map.replace!(:rooms, upd_rooms)
          index ->
            #Ersätt
            upd_quests = [quest | room.quests |> List.delete_at(index)]
            upd_room = map.rooms |> Map.replace!(:quests, upd_quests)
            upd_rooms = map.rooms |> Map.replace!(:quest, upd_room)
            upd_map = map |> Map.replace!(:rooms, upd_rooms)
        end
    end
  end
  def set_quest_pics(map, what req, val, pid) do end

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
  def create_user(id) do end
end
