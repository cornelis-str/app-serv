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
      {:get, pid, thing} -> 
        case thing do
          {:userID} -> send pid, user_data |> Map.get(:userId)
          {:notifs} -> send pid, user_data |> Map.get(:notifs)
          {:friends, userID} ->
            get_friend user_data, userID, pid
          {:rooms, roomID} ->
            get_room user_data, roomID, pid
          {:quest, questID} ->
            get_quest user_data, questID, pid
          {:quest_pic, resID} ->
            get_quest_pics user_data, resID, pid
          {:has_new} -> 
            send pid, user_data |> Map.get(:has_new)
        end
        user_data_handler(user_data)
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
          {:quest, questID} ->
            set_quest user_data, questID, value, pid
          {:quest_pic, resID} ->
            set_quest_pics user_data, resID, value, pid
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

  def get_friend(map, userID, pid) do
    friend = (map |> Map.get(:friends) |> Enum.find(nil, fn({:friend, %{:userID => x, _}}) -> x == userID end))
    send pid, friend
  end

  def get_room(map, roomID, pid) do
    room = (map.rooms |> Enum.find(fn(%{:roomID => x, _}) -> x == roomID end))
    send pid, room
  end

  def get_quest(map, resID, pid) do
    [username, roomname, questname] = String.split(resID, "@")
    room = (map.rooms |> Enum.find(fn(%{:roomID => x, _}) -> x == "#{username}@#{roomname}" end))
    quest = (room.quests |> Enum.find(fn({:quest, {:resID, resID2, _, _}}) -> resID2 == resID end))
    send pid, quest
  end

  def get_quest_pics(map, resID, pid) do
    [username, roomname, questname, missionPart, thingName] = String.split(resID, "@")
    room = (map.rooms |> Enum.find(fn(%{:roomID => x, _}) -> x == "#{username}@#{roomname}" end))
    quest_pic = (room.quest_pics |> Enum.find(fn({:quest_pic, {:resID, resID2, _, _}}) -> resID2 == resID end))
    send pid, quest_pic
  end

  def set_notif(map, req, val, pid) do
    case val do
      0 -> List.delete(data.notifs, req)
      _ ->
        Enum.member?(data.notifs, val)
        |> case do
          true -> send pid, {:memo, :ok}
          false ->
            map
            |> Map.replace!(:notifs, [val | data.notifs])
            send pid, {:memo, :ok}
          end
    end
  end

  def set_friend(map, req, val, pid) do end
  def set_room(map, req, val, pid) do end

  # room = %{
  # :owner => "Amandaaaaaa"
  # :name => "Super Duper Room",
  # :topic => "",
  # :icon => <<ByteArray>>
  # :users => [{:user, userID}, etc...]
  # :quests => [%{:questID => questID, :quest => <JsonString>}]
  # :quest_pics => [%{:quest_picID => quest_picID, :pic => <<ByteArray>>}]
  # }
  def set_quest(map, questID, quest, val, pid) do
    case val do
      :del ->
        map.quests |> List.delete(quest)
        send pid, {:ok}
      :add ->
        Enum.member?(map.quests, quest)
        |> case do
          true ->
            #Ersätt

          false ->
            #Lägg till
        end
    end
  end
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
