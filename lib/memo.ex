defmodule Memo do
  require Logger

  # Memos interna struktur
  # user_data = %{
  # :user_id => lolcat,
  # :notifs => [%{:friend_request => %{:from => lolcat, :to => doggo}}, %{:room_invite => %{:room => [], :to => lolcat}}, etc...],
  # :friends => [{:friend, %{:user_id => user_id, :friends => []}}, etc...],
  # :rooms => [%{:room_id => room_id}, etc...],
  # :hasNew => false | true
  # }

  # Parsas i app_serv get_req
  # user_data_update = %{
  # :user_id => lolcat,
  # :notifs => [%{:friend_request => %{:from => lolcat, :to => doggo}}, %{:room_invite => %{:room => [], :to => lolcat}}, etc...],
  # :friends => [{:friend, %{:user_id => user_id, :friends => []}}, etc...],
  # :rooms => [%{:room_id => room_id, :room => room_data}, etc...],
  # :hasNew => false | true
  # }

  # Memos interna struktur
  # room_data = %{
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
    {:ok, pid} = Task.Supervisor.start_child(Memo.TaskSupervisor, fn -> memo_mux([]) end)
    Process.register(pid, :memo_mux)
    spawn(fn -> file_mux(file_path) end) |> Process.register(:file_mux)
  end

  def memo_mux(user_pid_list, room_pid_list) do
    receive do
      {:user, {user_id, action = {method, thing, _}}} ->

        case user_pid_list[user_id] do

          nil when method == :create_user ->
            new_user_pid = user_pid_list |> Map.put(user_id, spawn fn -> user_data_handler(thing) end)
            send user_pid_list[user_id], action
            memo_mux new_user_pid, room_pid_list

          nil when method == :add ->
            new_user_pid = user_pid_list |> Map.put(user_id, spawn fn -> load_user(user_id) |> user_data_handler() end)
            send user_pid_list[user_id], action
            memo_mux new_user_pid, room_pid_list

          pid ->
            send pid, action
            memo_mux user_pid_list, room_pid_list

        end

      {:room, {room_id, action = {method, thing, _}}} ->

        case room_pid_list[room_id] do

          nil when method == :add ->
            new_room_pid_list = room_pid_list |> Map.put(room_id, room_pid = spawn(fn -> room_data_handler(thing) end))
            send room_pid, action
            memo_mux user_pid_list, new_room_pid_list

          room_pid ->
            send room_pid, action
            memo_mux user_pid_list, room_pid_list
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
          send :file_mux, {:quit}
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
            get_rooms user_data, pid           #TODO implementera get_rooms
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

          {:rooms, room_id, what} ->
            set_rooms user_data, pid           #TODO implementera set_rooms

          {:has_new} ->
            user_data
            |> Map.replace!(:has_new, value)

        end
        |> user_data_handler()              # IT WORKS MTFKER!!!

      {:save, user_id} -> send :file_mux, {:save, {user_id, user_data}}
      {:quit} -> :ok
    end
  end

  def get_friend(user_data, user_id, pid) do
    friend = (user_data.friends |> Enum.find(fn({:friend, %{:user_id => x, :friends => _}}) -> x == user_id end))
    send pid, friend
  end

  #TODO implement
  def get_rooms(user_data, pid) do end

  #TODO använd room_data/room_map istället för user_data/user_data
  def get_room(user_data, room_id, pid) do
    room = (user_data.rooms |> Enum.find(fn(%{:room_id => x, :room => _}) -> x == room_id end))
    send pid, room
  end

  #TODO använd room_data/room_map istället för user_data/user_data
  def get_quest(user_data, resource_id, pid) do
    [username, roomname, _] = String.split(resource_id, "@")
    room = (user_data.rooms |> Enum.find(fn(%{:room_id => x, :room => _}) -> x == "#{username}@#{roomname}" end))
    quest = (room.quests |> Enum.find(fn(%{:quest_id => x, :quest => _}) -> x == resource_id end))
    send pid, quest
  end

  #TODO använd room_data/room_map istället för user_data/user_data
  def get_quest_pics(user_data, resource_id, pid) do
    [username, roomname, _, _, _] = String.split(resource_id, "@")
    room = (user_data.rooms |> Enum.find(fn(%{:room_id => x, :room => _}) -> x == "#{username}@#{roomname}" end))
    quest_pic = (room.quest_pics |> Enum.find(fn(%{:quest_pic_id => x, :pic => _}) -> x == resource_id end))
    send pid, quest_pic
  end

  def set_notif(user_data, method, notif, pid) do
    case method do
      :del -> user_data.notifs |> List.delete(notif)
      :add ->
        user_data.notifs
        |> Enum.member?(notif)
        |> case do
          true -> send pid, {:memo, :ok}
          false ->
            user_data |> Map.replace!(:notifs, [notif | user_data.notifs])
            send pid, {:memo, :ok}
          end
    end
  end

  def set_friend(user_data, method, user_id, friend, pid) do
    user_data.friends
    |> Enum.find_index(fn {:friend, %{:user_id => ^user_id, :friends => _}} -> true end)
    |> case do
      nil when method == :add ->
        user_data
        |> Map.replace!(:friends, [friend | user_data.friends])

      nil when method == :del ->
        send pid, {:memo, "Can't delete nonexisting"}

      index ->
        case method do
          :add ->
            user_data
            |> Map.replace!(:friends, user_data.friends)

          :del ->
            user_data
            |> Map.replace!(:friends, [friend | user_data.friends |> List.delete_at(index)])
        end
    end
  end

  # TODO implementera
  def set_rooms(user_data, pid) do end

  #TODO använd room_data/room_map istället för user_data/user_data
  def set_room(user_data, method, room_id, room_part, part, pid) do
    user_data.rooms
    |> Enum.find(fn(%{:room_id => ^room_id, :room => _}) -> true end)
    |> case do
      nil when method == :add -> user_data |> Map.replace!(:rooms, [part | user_data.rooms])

      nil when method == :del -> send pid, {:memo, "Can't delete nonexisting"}

      %{:room_id => _, :room => _} ->
        case room_part do
          :room when method == :add ->
            user_data |> Map.replace!(:rooms, [part | user_data.rooms
            |> Enum.find(fn(%{:room_id => ^room_id, :room => _}) -> true end)
            |> List.delete()])

          :room when method == :del ->
            user_data |> Map.replace!(:rooms,
            user_data.rooms
            |> Enum.find(fn (%{:room_id => ^room_id, :room => _}) -> true end)
            |> List.delete() )

          :owner ->
            user_data |> Map.replace!(:owner, part)

          :name ->
            user_data |> Map.replace!(:name, part)

          :topic ->
            user_data |> Map.replace!(:topic, part)

          :icon ->
            user_data |> Map.replace!(:icon, part)

          :users when method == :add ->
            user_data.users
            |> Enum.find_index(fn(^part) -> true end)
            |> case do
              nil ->
                user_data |> Map.replace!(:users, [part | user_data.users])
              index ->
                user_data |> Map.replace!(:users, [part |
                user_data.users
                |> List.delete_at(index)])
            end

          :users when method == :del ->
            user_data |> Map.replace!(:users,
            user_data.users
            |> List.delete_at(user_data.users
            |> Enum.find_index(fn(^part) -> true end)))

          _ -> send pid, {:memo, "SYNTAX ERROR"}
        end
    end
  end

  #TODO använd room_data/room_map istället för user_data/user_data
  def set_quest(user_data, action, quest_id, quest, pid) do
    [username, roomname, _] = String.split(quest_id, "@")
    room = (user_data.rooms |> Enum.find(fn(%{:room_id => x, :room => _}) -> x == "#{username}@#{roomname}" end))
    case action do
      :del ->
        room.quests |> Enum.find_index(fn(%{:quest_id => ^quest_id, :quest => _}) -> true end)
        |> case do
          nil->
            send pid, {:memo, "Cannot remove files that do not exist"}
          index ->
            upd_quests = room.quests |> List.delete_at(index)
            upd_room = user_data.rooms |> Map.replace!(:quests, upd_quests)
            upd_rooms = user_data.rooms |> Map.replace!(:quest, upd_room)
            upd_map = user_data |> Map.replace!(:rooms, upd_rooms)
        end
      :add ->
        room.quests |> Enum.find_index(fn(%{:quest_id => ^quest_id, :quest => _}) -> true end)
        |> case do
          nil ->
            #Lägg till
            upd_quests = [quest | room.quests]
            upd_room = user_data.rooms |> Map.replace!(:quests, upd_quests)
            upd_rooms = user_data.rooms |> Map.replace!(:quest, upd_room)
            upd_map = user_data |> Map.replace!(:rooms, upd_rooms)
          index ->
            #Ersätt
            upd_quests = [quest | room.quests |> List.delete_at(index)]
            upd_room = user_data.rooms |> Map.replace!(:quests, upd_quests)
            upd_rooms = user_data.rooms |> Map.replace!(:quest, upd_room)
            user_data |> Map.replace!(:rooms, upd_rooms)
        end
    end
  end

  #TODO använd room_data/room_map istället för user_data/user_data
  def set_quest_pics(user_data, action, quest_pic_id, pic, pid) do
    [username, roomname, _, _, _] = String.split(quest_pic_id, "@")
    room = (user_data.rooms |> Enum.find(fn(%{:room_id => x, :room => _}) -> x == "#{username}@#{roomname}" end))
    case action do
      :del ->
        room.quest_pics |> Enum.find_index(fn(%{:quest_pic_id => ^quest_pic_id, :quest_pic => _}) -> true end)
        |> case do
          nil->
            send pid, {:memo, "Cannot remove files that do not exist"}
          index ->
            upd_quests_pic = room.quest_pics |> List.delete_at(index)
            upd_room = user_data.rooms |> Map.replace!(:quest_pics, upd_quests_pic)
            upd_rooms = user_data.rooms |> Map.replace!(:quest_pic, upd_room)
            upd_map = user_data |> Map.replace!(:rooms, upd_rooms)
        end
      :add ->
        room.quest_pics |> Enum.find_index(fn(%{:quest_pic_id => ^quest_pic_id, :quest_pic => _}) -> true end)
        |> case do
          nil ->
            #Lägg till
            upd_quests_pic = [pic | room.quest_pics]
            upd_room = user_data.rooms |> Map.replace!(:quest_pics, upd_quests_pic)
            upd_rooms = user_data.rooms |> Map.replace!(:quest_pic, upd_room)
            upd_map = user_data |> Map.replace!(:rooms, upd_rooms)
          index ->
            #Ersätt
            upd_quests_pic = [pic | room.quest_pics |> List.delete_at(index)]
            upd_room = user_data.rooms |> Map.replace!(:quest_pics, upd_quests_pic)
            upd_rooms = user_data.rooms |> Map.replace!(:quest_pic, upd_room)
            user_data |> Map.replace!(:rooms, upd_rooms)
        end
    end
  end

  def room_data_handler(room_data) do
    receive do

      {:get, pid, {:quest, quest_id}} ->
        get_quest room_data, quest_id, pid          #TODO updatera för att använda room_map

      {:get, pid, {:quest_pic, resource_id}} ->
        get_quest_pics room_data, resource_id, pid  #TODO updatera för att använda room_map

      {:set, pid, {:quest, quest_id, what}} ->
        set_quest room_data, what, quest_id, value, pid #TODO updatera för att använda room_map

      {:set, pid, {:quest_pic, resource_id, what}} ->
        set_quest_pics room_data, what, resource_id, value, pid #TODO updatera för att använda room_map

    end

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

  # TODO ladda user från minnet med file_mux
  def load_user(user_id) do end
end
