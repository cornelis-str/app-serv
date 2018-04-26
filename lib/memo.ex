defmodule Memo do
  require Logger

  # user_data = %{
  # :user_id => lolcat,
  # :notifs => [%{:friend_request => %{:from => lolcat, :to => doggo}}, %{:room_invite => %{:room => [], :to => lolcat}}, etc...],
  # :friends => [{:friend, %{:user_id => user_id, :friends => []}}, etc...],
  # :rooms => [%{:room_id => room_id, :room => room}, etc...],
  # :hasNew => false | true
  # }
  # room = %{
  # :owner => "Kor-Nelzizandaaaaaa"
  # :name => "Super Duper Room",
  # :topic => "Underground Bayblade Cabal",
  # :icon => <<ByteArray>>
  # :users => [{:user, user_id}, etc...]
  # :quests => [%{:quest_id => quest_id, :quest => <JsonString>}]
  # :quest_pics => [%{:quest_pic_id => quest_pic_id, :pic => <<ByteArray>>}]
  # }
  # Hämtar och ändrar user data på begäran.

  def start(file_path) do
    # Ta bort kommentering i lib/application.ex för att det ska fungera
    {:ok, _} = Task.Supervisor.start_child(Memo.TaskSupervisor, fn -> memo_mux([]) end)
    spawn(fn -> file_mux(file_path) end) |> Process.register(:fmux)
  end

  def memo_mux(user_pid_list, room_pid_list) do
    receive do
      {:user, {user_id, action}} ->
        case user_pid_list[user_id] do
          nil ->
            user_pid_list |> Map.put(user_id, spawn fn -> create_user(user_id) |> user_data_handler() end)
            send user_pid_list[user_id], action
          pid -> send pid, action
        end
        memo_mux user_pid_list

      {:room, {room_id, action}} ->
        case room_pid_list[room_id] do

        end

      {:quit} ->
          # skicka :save och :quit till alla user_data_handler processer
          save_exit = fn([h|t], f) ->
            case h do
              {user_id, pid} ->
                send pid, {:save, user_id}
                send pid, {:quit}
                f.(t,f)
              end
          end
          save_exit.(user_pid_list |> Map.to_list(), save_exit)

          # TODO gå inte vidare för än alla barnprocesser är döda
          send :ld, {:quit}
          send :fmux, {:quit}
    end
  end

  def user_data_handler(user_data) do
    receive do
      {:get, pid, thing} ->
        case thing do
          {:user_id} -> send pid, user_data.user_id
          {:notifs} -> send pid, user_data.notifs
          {:friends, user_id} ->
            get_friend user_data, user_id, pid
          {:rooms, room_id} ->
            get_room user_data, room_id, pid
          {:quest, quest_id} ->
            get_quest user_data, quest_id, pid
          {:quest_pic, resource_id} ->
            get_quest_pics user_data, resource_id, pid
          {:has_new} ->
            send pid, user_data.has_new
        end
        user_data_handler(user_data)
      {:set, pid, action, value} ->
        case action do
          {:user_id} -> user_data |> Map.put(:user_id, value)
          {:notifs, what} ->
            set_notif user_data, what, value, pid

          {:friends, user_id, what} ->
            set_friend user_data, what, user_id, value, pid

          {:rooms, room_id, room_part, what} ->
            set_room user_data, what, room_id, room_part, value, pid

          {:quest, quest_id, what} ->
            set_quest user_data, what, quest_id, value, pid

          {:quest_pic, resource_id, what} ->
            set_quest_pics user_data, what, resource_id, value, pid

          {:has_new} ->
            user_data
            |> Map.replace!(:has_new, value)

        end
        |> user_data_handler()              # IT WORKS MTFKER!!!

      {:save, user_id} -> send :fmux, {:save, {user_id, user_data}}
      {:quit} -> :ok
    end
  end

  def get_friend(map, user_id, pid) do
    friend = (map.friends |> Enum.find(fn({:friend, %{:user_id => x, :friends => _}}) -> x == user_id end))
    send pid, friend
  end

  def get_room(map, room_id, pid) do
    room = (map.rooms |> Enum.find(fn(%{:room_id => x, :room => _}) -> x == room_id end))
    send pid, room
  end

  def get_quest(map, resource_id, pid) do
    [username, roomname, _] = String.split(resource_id, "@")
    room = (map.rooms |> Enum.find(fn(%{:room_id => x, :room => _}) -> x == "#{username}@#{roomname}" end))
    quest = (room.quests |> Enum.find(fn(%{:quest_id => x, :quest => _}) -> x == resource_id end))
    send pid, quest
  end

  def get_quest_pics(map, resource_id, pid) do
    [username, roomname, _, _, _] = String.split(resource_id, "@")
    room = (map.rooms |> Enum.find(fn(%{:room_id => x, :room => _}) -> x == "#{username}@#{roomname}" end))
    quest_pic = (room.quest_pics |> Enum.find(fn(%{:quest_pic_id => x, :pic => _}) -> x == resource_id end))
    send pid, quest_pic
  end

  def set_notif(map, method, notif, pid) do
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

  def set_friend(map, method, user_id, friend, pid) do
    map.friends
    |> Enum.find_index(fn {:friend, %{:user_id => ^user_id, :friends => _}} -> true end)
    |> case do
      nil when method == :add ->
        map
        |> Map.replace!(:friends, [friend | map.friends])

      nil when method == :del ->
        send pid, {:memo, "Can't delete nonexisting"}

      index ->
        case method do
          :add ->
            map
            |> Map.replace!(:friends, map.friends)

          :del ->
            map
            |> Map.replace!(:friends, [friend | map.friends |> List.delete_at(index)])
        end
    end
  end

  def set_room(map, method, room_id, room_part, part, pid) do
    map.rooms
    |> Enum.find(fn(%{:room_id => ^room_id, :room => _}) -> true end)
    |> case do
      nil when method == :add -> map |> Map.replace!(:rooms, [part | map.rooms])

      nil when method == :del -> send pid, {:memo, "Can't delete nonexisting"}

      %{:room_id => _, :room => _} ->
        case room_part do
          :room when method == :add ->
            map |> Map.replace!(:rooms, [part | map.rooms
            |> Enum.find(fn(%{:room_id => ^room_id, :room => _}) -> true end)
            |> List.delete()])

          :room when method == :del ->
            map |> Map.replace!(:rooms,
            map.rooms
            |> Enum.find(fn (%{:room_id => ^room_id, :room => _}) -> true end)
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


  def set_quest(map, action, quest_id, quest, pid) do
    [username, roomname, _] = String.split(quest_id, "@")
    room = (map.rooms |> Enum.find(fn(%{:room_id => x, :room => _}) -> x == "#{username}@#{roomname}" end))
    case action do
      :del ->
        room.quests |> Enum.find_index(fn(%{:quest_id => ^quest_id, :quest => _}) -> true end)
        |> case do
          nil->
            send pid, {:memo, "Cannot remove files that do not exist"}
          index ->
            upd_quests = room.quests |> List.delete_at(index)
            upd_room = map.rooms |> Map.replace!(:quests, upd_quests)
            upd_rooms = map.rooms |> Map.replace!(:quest, upd_room)
            upd_map = map |> Map.replace!(:rooms, upd_rooms)
        end
      :add ->
        room.quests |> Enum.find_index(fn(%{:quest_id => quest_id, :quest => _}) -> true end)
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
            map |> Map.replace!(:rooms, upd_rooms)
        end
    end
  end

  def set_quest_pics(map, action, quest_pic_id, pic, pid) do
    [username, roomname, _, _, _] = String.split(quest_pic_id, "@")
    room = (map.rooms |> Enum.find(fn(%{:room_id => x, :room => _}) -> x == "#{username}@#{roomname}" end))
    case action do
      :del ->
        room.quest_pics |> Enum.find_index(fn(%{:quest_pic_id => ^quest_pic_id, :quest_pic => _}) -> true end)
        |> case do
          nil->
            send pid, {:memo, "Cannot remove files that do not exist"}
          index ->
            upd_quests_pic = room.quest_pics |> List.delete_at(index)
            upd_room = map.rooms |> Map.replace!(:quest_pics, upd_quests_pic)
            upd_rooms = map.rooms |> Map.replace!(:quest_pic, upd_room)
            upd_map = map |> Map.replace!(:rooms, upd_rooms)
        end
      :add ->
        room.quest_pics |> Enum.find_index(fn(%{:quest_pic_id => ^quest_pic_id, :quest_pic => _}) -> true end)
        |> case do
          nil ->
            #Lägg till
            upd_quests_pic = [pic | room.quest_pics]
            upd_room = map.rooms |> Map.replace!(:quest_pics, upd_quests_pic)
            upd_rooms = map.rooms |> Map.replace!(:quest_pic, upd_room)
            upd_map = map |> Map.replace!(:rooms, upd_rooms)
          index ->
            #Ersätt
            upd_quests_pic = [pic | room.quest_pics |> List.delete_at(index)]
            upd_room = map.rooms |> Map.replace!(:quest_pics, upd_quests_pic)
            upd_rooms = map.rooms |> Map.replace!(:quest_pic, upd_room)
            map |> Map.replace!(:rooms, upd_rooms)
        end
    end
  end

  def room_data_handler do

  end

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

  # TODO
  # Skapar ny user
  def create_user(user_id) do end
end
