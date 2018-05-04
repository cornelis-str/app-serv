defmodule Memo do
  require Logger

  # Använda Elixirs inbyggda documenterings format/system istället för
  # denna vägg med oformaterad test?
  
  # TODO: Skriv upp meddelande-syntax för alla operationer som memo_mux ska
  # kunna godkänna.

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
    {:ok, pid} = Task.Supervisor.start_child(Serv.TaskSupervisor, fn -> memo_mux(%{}, %{}) end)
    Process.register(pid, :memo_mux)

    #spawn(fn -> file_mux(file_path) end) |> Process.register(:file_mux)
  end

  defp memo_mux(user_pid_list, room_pid_list) do
    Logger.info "memo_mux"
    receive do
      {:user, user_id, action = {method, thing}} ->

        case method do

          :create_user ->
            #IO.inspect thing, limit: :infinity
            new_user_pid_list = user_pid_list
            |> Map.put(user_id, spawn fn -> Memo.user.data_handler(thing) end)
            #IO.inspect new_user_pid_list, limit: :infinity
            memo_mux new_user_pid_list, room_pid_list

          :add ->
            new_user_pid_list = user_pid_list
            |> Map.put(user_id, spawn fn -> load_user(user_id) |> Memo.user.data_handler() end)
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
        new_room_pid_list = room_pid_list |> Map.put(room_id, spawn(fn -> Memo.room.data_handler(thing) end))
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

            new_room_pid_list = room_pid_list |> Map.put(room_id, spawn(fn -> Memo.room.data_handler(new_room) end))
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
      catch_all ->
        IO.inspect catch_all, limit: :infinity
        memo_mux(user_pid_list, room_pid_list)
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
