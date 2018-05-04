
defmodule Memo do
  require Logger

  # TODO: vänner ska ha bilder? - senare problem. Börja med quests med bilder.
  # Memos interna struktur
  # user_data = %{
  # :user_id => lolcat,
  # :notifs => [%{:friend_request => %{:from => lolcat, :to => doggo}}, %{:room_invite => %{:room => [], :to => lolcat}},
  # %{:submitted => %{:from => user_id, :to => user_id, :quest_id}, :pic => bytearray|nil, :string => str|nil}, etc...],
  # :friends => [%{:friend, %{:user_id => user_id, :friends => [%{:user_id, amanda}, %{:user_id, marcus}]}}, etc...],
  # :rooms => [%{:room_id => room_id}, etc...],
  # :hasNew => false | true
  # }

  # Parsas i app_serv get_req
  # user_data_update = %{
  # :user_id => lolcat,
  # :notifs => [%{:friend_request => %{:from => lolcat, :to => doggo}}, %{:room_invite => %{:room => [], :to => lolcat}}, etc...],
  # :friends => [%{:friend, %{:user_id => user_id, :friends => []}}, etc...],
  # :rooms => [%{:room_id => room_id, :room => room_data}, etc...],
  # }

  # Memos interna struktur
  # room_data = %{
  # :owner => "Kor-Nelzizandaaaaaa",
  # :name => "Super Duper Room",
  # :topic => "Underground Bayblade Cabal",
  # :icon => <<ByteArray>>
  # :users => [%{:user, user_id}, etc...]
  # :quests => [%{:quest_id => quest_id, :quest => <JsonString>}]
  # :quest_pics => [%{:quest_pic_id => quest_pic_id, :pic => <<ByteArray>>}]
  # }

  # Hämtar och ändrar user data på begäran.
  def start() do
    # Ta bort kommentering i lib/application.ex för att det ska fungera

    {:ok, pid} = Task.Supervisor.start_child(Serv.TaskSupervisor, fn -> memo_mux(%{}, %{}) end)
    Process.register(pid, :memo_mux)

    #spawn(fn -> file_mux(file_path) end) |> Process.register(:file_mux)
  end

  def memo_mux(user_pid_list, room_pid_list) do
    Logger.info "memo_mux"
    receive do
      {:user, user_id, action = {method, thing}} ->

        case method do

          :create_user ->
            #IO.inspect thing, limit: :infinity
            new_user_pid_list = user_pid_list
            |> Map.put(user_id, spawn fn -> user_data_handler(thing) end)
            #IO.inspect new_user_pid_list, limit: :infinity
            memo_mux new_user_pid_list, room_pid_list

          :add ->
            new_user_pid_list = user_pid_list
            |> Map.put(user_id, spawn fn -> load_user(user_id) |> user_data_handler() end)
            send user_pid_list[user_id], action
            memo_mux new_user_pid_list, room_pid_list

          _ -> Logger.info "(╯ರ ~ ರ）╯︵ ┻━┻"
        end
      {:user, user_id, action = {method, _, _}} ->

        case user_pid_list[user_id] do

          nil ->
            IO.inspect method, label: ":user user_pid_list nil"
            Logger.info "(╯ರ ~ ರ）╯︵ ┻━┻"

          pid ->
            Logger.info ":user #{user_id} #{method}"
            #IO.inspect method
            send pid, action
            memo_mux user_pid_list, room_pid_list
        end

      {:room, room_id, {method, thing}} when method == :add ->
        #Logger.info ":room :add"
        # Ingen felhantering, går troligen att spawna oändligt med processer
        new_room_pid_list = room_pid_list |> Map.put(room_id, spawn(fn -> room_data_handler(thing) end))
        memo_mux user_pid_list, new_room_pid_list
        Logger.info "(╯ರ ~ ರ）╯︵ ┻━┻ depricated, read the LOGS DAMNIT!!!"

        #send room_pid_list[room_id], action


      {:room, room_id, action = {method, _, _}} ->

        case room_pid_list[room_id] do

          nil ->
            Logger.info " ########### Creating room room_id: #{room_id}"
            [owner_name, room_name] = room_id |> String.split("@")

            IO.inspect owner_name, label: "creating room owner_name"
            IO.inspect room_name, label: "creating room room_name"

            new_room = %{
            :owner => owner_name,
            :name => room_name,
            :topic => nil,
            :icon => nil,
            :users => [],
            :quests => [],
            :quest_pics => []
            }

            new_room_pid_list = room_pid_list |> Map.put(room_id, spawn(fn -> room_data_handler(new_room) end))
            Logger.info "room created"
            send :memo_mux, {:user, owner_name, {:set, self(), {:rooms, room_id, :add}}}
            Logger.info "adding room to user"
            memo_mux user_pid_list, new_room_pid_list
            IO.inspect method, label: ":room room_pid_list nil"

          room_pid ->
            send room_pid, action
            memo_mux user_pid_list, room_pid_list
        end

      {:quit} ->
          # skicka :save och :quit till alla user_data_handler processer
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
      catch_all ->
        IO.inspect catch_all, limit: :infinity
        memo_mux(user_pid_list, room_pid_list)
    end
  end

  def user_data_handler(user_data) do
    Logger.info "user_data_handler"
    IO.inspect user_data, limit: :infinity
    receive do
      ### Getters ###
      {:get, pid, {:user}} ->
        send pid, user_data
        user_data_handler(user_data)

      {:get, pid, {:user_id}} ->
        send pid, user_data.user_id
        user_data_handler(user_data)

      {:get, pid, {:notifs}} ->
        #Logger.info ":get notifs"
        send pid, user_data.notifs
        #IO.inspect user_data.notifs, limit: :infinity
        user_data_handler(user_data)

      {:get, pid, {:friends}} ->
        send pid, user_data.friends
        user_data_handler(user_data)

      {:get, pid, {:friend, user_id}} ->
        get_friend user_data, user_id, pid
        user_data_handler(user_data)

      {:get, pid,{:room_list}} ->
        #Logger.info ":get rooms"
        get_room_list user_data, pid
        user_data_handler(user_data)

      {:get, pid,{:has_new}} ->
        send pid, user_data.has_new
        user_data_handler(user_data)

      ### Setters ###
      {:set, pid, {:user_id, value}} ->
        user_data
        |> Map.put(:user_id, value)
        |> user_data_handler()

      {:set, pid, {:notifs, value, how}} ->
        #Logger.info ":set notifs"
        t = set_notif user_data, how, value, pid
        #IO.inspect t, limit: :infinity
        user_data_handler(t)

      {:set, pid, {:friends, user_id, value, how}} ->
        #Logger.info ":set friends"
        new_user_data = set_friend user_data, how, user_id, value, pid
        #IO.inspect new_user_data, limit: :infinity
        user_data_handler(new_user_data)

      {:set, pid, {:rooms, room_id, how}} ->
        Logger.info ":set rooms"
        new = set_users_rooms user_data, how, room_id, pid
        #IO.inspect new, limit: :infinity
        user_data_handler(new)

      {:set, pid, {:has_new, value}} ->
        user_data
        |> Map.replace!(:has_new, value)
        |> user_data_handler()

      {:save, user_id} -> send :file_mux, {:save, {user_id, user_data}}
      {:quit} -> :ok
    end
  end

  # "how" can be :del or :add. With icons and text this is ignored.
  def room_data_handler(room_data) do
    receive do
      ### Getters ###
      {:get, pid, {:room}} ->
        Logger.info ":get :room"
        send pid, room_data
        room_data_handler(room_data)

      {:get, pid, {:room, room_part}} ->
        get_room room_data, room_part, pid
        room_data_handler(room_data)

      {:get, pid, {:quest, quest_id}} ->
        get_quest room_data, quest_id, pid
        room_data_handler(room_data)

      {:get, pid, {:quest_pic, resource_id}} ->
        get_quest_pics room_data, resource_id, pid
        room_data_handler(room_data)

      ### Setters ###
      {:set, pid, {:room, which_room_part, part_to_add, how}} ->
        set_room room_data, how, which_room_part, part_to_add, pid
        |> room_data_handler()

      {:set, pid, {:room, room_id, :del}} ->
        send pid, {:memo, "deleting room #{room_id}"}

      {:set, pid, {:quest, quest_id, quest, how}} ->
        set_quest room_data, how, quest_id, quest, pid
        |> room_data_handler()

      {:set, pid, {:quest_pic, resource_id, resource, how}} ->
        set_quest_pics room_data, how, resource_id, resource, pid
        |> room_data_handler()
    end
  end

  ### USER_DATA_HANDLER GETTERS ###
  def get_friend(user_data, user_id, pid) do
    #Logger.info "get_friend"
    friend = user_data.friends |> Enum.find(fn({:friend, %{:user_id => x, :friends => _}}) -> x == user_id end)
    #IO.inspect friend, limit: :infinity
    send pid, friend
  end

  def get_room_list(user_data, pid) do
    #Logger.info "get_room_list"
    #IO.inspect user_data.rooms
    send pid, {:memo, user_data.rooms}
  end

  ### USER_DATA_HANDLER SETTERS ###
  def set_notif(user_data, how, notif, pid) do
    user_data.notifs
    |> notif_member?(notif)
    |> case do

      nil when how == :add ->
        #Logger.info "false, add"
        user_data
        |> Map.replace!(:notifs, [notif | user_data.notifs])

      nil when how == :del ->
        #Logger.info "false, del"
        Logger.info {:memo, "Can't delete 'nothing'"}

      index when how == :add ->
        #Logger.info "true, add"
        user_data

      index when how == :del ->
        #Logger.info "true, del"
        user_data
        |> Map.replace!(:notifs, user_data.notifs |> List.delete_at(index))

    end
  end

  def notif_member?(list_of_notifs, notif = %{:submitted => %{:from => _, :to => _, :quest_id => _}, :pic => _, :string => _}) do
    list_of_notifs
    |> Enum.find_index(
      fn(x) ->
        case x do
          %{:submitted => %{:from => from, :to => to, :quest_id => id}, :pic => _, :string => _} ->
            from == notif.submitted.from && to == notif.submitted.to && id == notif.submitted.quest_id
          _ -> false
        end
      end
    )
  end
  def notif_member?(list_of_notifs, notif), do: list_of_notifs |> Enum.find_index(fn(x) -> x == notif end)

  def set_friend(user_data, how, user_id, friend, pid) do
    #Logger.info "set_friend"
    #IO.inspect user_data.friends, limit: :infinity
    user_data.friends
    |> Enum.find_index(fn(%{:friend => %{:user_id => x, :friends => _}}) -> x == user_id end)
    |> case do
      nil when how == :add ->
        #Logger.info "nil add"
        user_data
        |> Map.replace!(:friends, [friend | user_data.friends])

      nil when how == :del ->
        #Logger.info "nil del"
        Logger.info "#{pid}, {:memo, \"SYNTAX ERROR\"}"

      index when how == :add ->
        #Logger.info "index add"
        user_data
        |> Map.replace!(:friends, [friend | user_data.friends |> List.delete_at(index)])

      index when how == :del ->
        #Logger.info "index del"
        user_data
        |> Map.replace!(:friends, user_data.friends |> List.delete_at(index))
    end
  end

  def set_users_rooms(user_data, how, room_id, pid) do
    #Logger.info "set_users_rooms"
    user_data.rooms
    |> Enum.find_index(fn(%{:room_id => x}) -> x == room_id end)
    |> case do
      nil when how == :add ->
        #Logger.info "nil add"
        user_data
        |> Map.replace!(:rooms, [%{:room_id => room_id} | user_data.rooms])

      nil when how == :del ->
        Logger.info "#{pid}, {:memo, \"SYNTAX ERROR\"}"

      index when how == :del ->
        user_data
        |> Map.replace!(:rooms, user_data.rooms |> List.delete_at(index))

      _ when how == :add ->
        user_data
    end
  end

  ### ROOM_DATA_HANDLER GETTERS ###
  def get_room(room_data, room_part, pid) do
    case room_part do
      :owner -> send pid, room_data.owner
      :name -> send pid, room_data.name
      :topic -> send pid, room_data.topic
      :icon -> send pid, room_data.icon
      :users -> send pid, room_data.users
      :quests -> send pid, room_data.quests
      :quest_pics -> send pid, room_data.quest_pics
      _ -> send pid, {:memo, "SYNTAX ERROR"}
    end
  end

  def get_quest(room_data, quest_id, pid) do
    send pid, room_data.quests
    |> Enum.find(fn(%{:quest_id => ^quest_id, :quest => _}) -> true end)
  end

  def get_quest_pics(room_data, quest_pic_id, pid) do
    send pid, room_data.quest_pics
    |> Enum.find(fn(%{:quest_pic_id => ^quest_pic_id, :pic => _}) -> true end)
  end

  ### ROOM_DATA_HANDLER SETTERS ###
  def set_room(room_data, how, room_part, part, pid) do
    case room_part do
      :owner ->
        room_data |> Map.replace!(:owner, part)

      :name ->
        room_data |> Map.replace!(:name, part)

      :topic ->
        room_data |> Map.replace!(:topic, part)

      :icon ->
        room_data |> Map.replace!(:icon, part)

      :users when how == :add ->
        room_data.users
        |> Enum.find_index(fn(^part) -> true end)
        |> case do
              nil ->
                room_data
                |> Map.replace!(:users, [part | room_data.users])
              index ->
                room_data
                |> Map.replace!(:users, [part | room_data.users
                |> List.delete_at(index)])
            end

      :users when how == :del ->
        room_data
        |> Map.replace!(:users, room_data.users
        |> List.delete_at(room_data.users
        |> Enum.find_index(fn(^part) -> true end)))

      _ -> send pid, {:memo, "SYNTAX ERROR"}
    end
  end

  def set_quest(room_data, how, quest_id, quest, pid) do
    room_data.quests
    |> Enum.find_index(fn(%{:quest_id => x, :quest => _}) -> x == quest_id end)
    |> case do
      nil when how == :add ->
        #Lägg till
        room_data |> Map.replace!(:quests, [quest | room_data.quests])

      nil when how == :del ->
        Logger.info "#{pid}, {:memo, \"SYNTAX ERROR\"}"

      index when how == :add ->
        #Ersätt
        room_data
        |> Map.replace!(:quest, [quest | room_data.quests |> List.delete_at(index)])

      _ when how == :del ->
        Logger.info "#{pid}, {:memo, \"SYNTAX ERROR\"}"
    end
  end

  def set_quest_pics(room_data, how, quest_pic_id, pic, pid) do
    room_data.quest_pics
    |> Enum.find_index(fn(%{:quest_pic_id => x, :quest_pic => _}) -> x == quest_pic_id end)
    |> case do
      nil when how == :add ->
        room_data
        |> Map.replace!(:quest_pics, [pic | room_data.quest_pics])

      nil when how == :del ->
        Logger.info "#{pid}, {:memo, \"SYNTAX ERROR\"}"

      index when how == :add ->
        room_data
        |> Map.replace!(:quest_pics, [pic | room_data.quest_pics |> List.delete_at(index)])

      index when how == :del ->
        room_data
        |> Map.replace!(:quest_pics, [pic | room_data.quest_pics |> List.delete_at(index)])

    end
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
