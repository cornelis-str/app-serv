defmodule Memo_room do
  require Logger
  # "how" can be :del or :add. With icons and text this is ignored.
  def data_handler(room_data) do
    IO.inspect room_data, [label: "Memo Room:\n"]
    receive do
      ### Getters ###
      {:get, pid, {:room}} ->
        send pid, room_data
        data_handler(room_data)

      {:get, pid, {:room, room_part}} ->
        get_room(room_data, room_part, pid)
        data_handler(room_data)

      {:get, pid, {:quest, quest_id}} ->
        get_quest(room_data, quest_id, pid)
        data_handler(room_data)

      {:get, pid, {:quest_pic, resource_id}} ->
        get_quest_pics(room_data, resource_id, pid)
        data_handler(room_data)

      ### Setters ###
      {:set, pid, {:room, which_room_part, part_to_add, how}} ->
        set_room(room_data, how, which_room_part, part_to_add, pid)
        |> data_handler()

      {:set, pid, {:room, room_id, :del}} ->
        del_room(room_data.users, room_id)

      {:set, pid, {:quest, quest_id, quest, how}} ->
        set_quest(room_data, how, quest_id, quest, pid)
        |> data_handler()

      {:set, pid, {:quest_pic, resource_id, resource, how}} ->
        set_quest_pics(room_data, how, resource_id, resource, pid)
        |> data_handler()
    end
  end

  ### GETTERS ###
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
    |> Enum.find(fn(%{:quest_id => x, :quest => _}) -> x == quest_id end)
  end

  def get_quest_pics(room_data, quest_pic_id, pid) do
    send pid, room_data.quest_pics
    |> Enum.find(fn(%{:quest_pic_id => x, :pic => _}) -> x == quest_pic_id end)
  end

  ### SETTERS ###
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
        |> Enum.find_index(fn(x) -> x == part end)
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
        |> Enum.find_index(fn(x) -> x == part end)))

      _ -> send pid, {:memo, "SYNTAX ERROR"}
    end
  end

  def del_room([], _), do: :ok
  def del_room([user_id | t], room_id) do
    send :memo_mux, {:user, user_id, {:set, self(), {:room, room_id, :del}}}
    del_room(t, room_id)
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
end
