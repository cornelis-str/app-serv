defmodule Memo_user do
  require Logger
  def data_handler(user_data) do
    Logger.info "user_data_handler"
    IO.inspect user_data, limit: :infinity
    receive do
      ### Getters ###
      {:get, pid, {:user}} ->
        send pid, user_data
        data_handler(user_data)

      {:get, pid, {:user_id}} ->
        send pid, user_data.user_id
        data_handler(user_data)

      {:get, pid, {:notifs}} ->
        #Logger.info ":get notifs"
        send pid, user_data.notifs
        #IO.inspect user_data.notifs, limit: :infinity
        data_handler(user_data)

      {:get, pid, {:friends}} ->
        send pid, user_data.friends
        data_handler(user_data)

      {:get, pid, {:friend, user_id}} ->
        get_friend user_data, user_id, pid
        data_handler(user_data)

      {:get, pid,{:room_list}} ->
        #Logger.info ":get rooms"
        get_room_list user_data, pid
        data_handler(user_data)

      {:get, pid,{:has_new}} ->
        send pid, user_data.has_new
        data_handler(user_data)

      ### Setters ###
      {:set, pid, {:user_id, value}} ->
        user_data
        |> Map.put(:user_id, value)
        |> data_handler()

      {:set, pid, {:notifs, value, how}} ->
        #Logger.info ":set notifs"
        t = set_notif user_data, how, value, pid
        #IO.inspect t, limit: :infinity
        data_handler(t)

      {:set, pid, {:friends, user_id, value, how}} ->
        #Logger.info ":set friends"
        new_user_data = set_friend user_data, how, user_id, value, pid
        #IO.inspect new_user_data, limit: :infinity
        data_handler(new_user_data)

      {:set, pid, {:rooms, room_id, how}} ->
        Logger.info ":set rooms"
        new = set_users_rooms user_data, how, room_id, pid
        #IO.inspect new, limit: :infinity
        data_handler(new)

      {:set, pid, {:has_new, value}} ->
        user_data
        |> Map.replace!(:has_new, value)
        |> data_handler()

      {:save, user_id} -> send :file_mux, {:save, {user_id, user_data}}
      {:quit} -> :ok
    end
  end

  ### GETTERS ###
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

  ### SETTERS ###
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

  defp notif_member?(list_of_notifs, notif = 
    %{:submitted => %{:from => _, :to => _, :quest_id => _}, :pic => _, :string => _}) do
    list_of_notifs
    |> Enum.find_index(
      fn(x) ->
        case x do
          %{:submitted => %{:from => from, :to => to, :quest_id => id}, :pic => _, :string => _} ->
            from == notif.submitted.from && 
              to == notif.submitted.to && 
                id == notif.submitted.quest_id
          _ -> false
        end
      end
    )
  end
  defp notif_member?(list_of_notifs, notif) do 
    list_of_notifs |> Enum.find_index(fn(x) -> x == notif end)
  end

  defp set_friend(user_data, how, user_id, friend, pid) do
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

  defp set_users_rooms(user_data, how, room_id, pid) do
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
end
