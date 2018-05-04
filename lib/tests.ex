defmodule Tests do
  require Logger

  def create_user_get_user_test do
    user = %{
      :user_id => "plop",
      :notifs => [],
      :friends => [],
      :rooms => [],
      :has_new => false
    }

    send :memo_mux, {:user, "plop", {:create_user, user}}
    send :memo_mux, {:user, "plop", {:get, self(), {:user}}}
    receive do
      thing -> thing
    end
  end

  def set_get_user_id_test do
    create_user_get_user_test()
    send :memo_mux, {:user, "plop", {:set, self(), {:user_id, "plip"}}}
    send :memo_mux, {:user, "plop", {:get, self(), {:user_id}}}
    receive do
      t -> t
    end
  end

  def set_get_notifs_test do
    create_user_get_user_test()
    friend_request = %{:friend_request => %{:from => "lolcat", :to => "doggo"}}
    room_invite = %{:room_invite => %{:room => [], :to => "doggo"}}
    quest_invite =
      %{:submitted => %{:from => "lolcat", :to => "doggo", :quest_id => "Run Damn It"}, :pic => "x", :string => "hi"}
    quest_accept = %{:accepted => %{:quest_id => "quest_id"}}

    send :memo_mux, {:user, "plop", {:set, self(), {:notifs, friend_request, :add}}}
    send :memo_mux, {:user, "plop", {:get, self(), {:notifs}}}

    receive do
      t ->
        Logger.info "notifs should have 1 notif"
        IO.inspect t, limit: :infinity
    end

    send :memo_mux, {:user, "plop", {:set, self(), {:notifs, room_invite, :add}}}
    send :memo_mux, {:user, "plop", {:get, self(), {:notifs}}}

    receive do
      t ->
        Logger.info "notifs should have 2 notifs"
        IO.inspect t, limit: :infinity
    end

    send :memo_mux, {:user, "plop", {:set, self(), {:notifs, quest_invite, :add}}}
    send :memo_mux, {:user, "plop", {:get, self(), {:notifs}}}

    receive do
      t ->
        Logger.info "notifs should have 3 notifs"
        IO.inspect t, limit: :infinity
    end

    send :memo_mux, {:user, "plop", {:set, self(), {:notifs, quest_accept, :add}}}
    send :memo_mux, {:user, "plop", {:get, self(), {:notifs}}}

    receive do
      t ->
        Logger.info "notifs should have 4 notifs"
        IO.inspect t, limit: :infinity
    end

    send :memo_mux, {:user, "plop", {:set, self(), {:notifs, friend_request, :del}}}
    send :memo_mux, {:user, "plop", {:set, self(), {:notifs, room_invite, :del}}}
    send :memo_mux, {:user, "plop", {:set, self(), {:notifs, quest_invite, :del}}}
    send :memo_mux, {:user, "plop", {:set, self(), {:notifs, quest_accept, :del}}}
    send :memo_mux, {:user, "plop", {:get, self(), {:notifs}}}

    receive do
      t ->
        Logger.info "notifs should be empty"
        IO.inspect t, limit: :infinity
    end
  end

  def set_get_friends_test do
    create_user_get_user_test()

    friend1 = {:friend, %{:user_id => "user_id", :friends => [{:user_id, "lolcat"}, {:user_id, "doggo"}]}}
    friend2 = {:friend, %{:user_id => "other_user_id", :friends => [{:user_id, "lolcat"}, {:user_id, "doggo"}]}}

    send :memo_mux, {:user, "plop", {:set, self(), {:friends, "user_id", friend1, :add}}}
    send :memo_mux, {:user, "plop", {:set, self(), {:friends, "other_user_id", friend2, :add}}}

    send :memo_mux, {:user, "plop", {:get, self(), {:friend, "user_id"}}}

    receive do
      t ->
        Logger.info "there shoud be user_id friend"
        IO.inspect t, limit: :infinity
    end

    send :memo_mux, {:user, "plop", {:get, self(), {:friend, "other_user_id"}}}

    receive do
      t ->
        Logger.info "there shoud be other_user_id friend"
        IO.inspect t, limit: :infinity
    end
  end

  def set_get_rooms_test do
    create_user_get_user_test()
    send :memo_mux, {:user, "plop", {:set, self(), {:rooms, "room", :add}}}
    send :memo_mux, {:user, "plop", {:set, self(), {:rooms, "another room", :add}}}

    send :memo_mux, {:user, "plop", {:get, self(), {:room_list}}}

    receive do
      t ->
        Logger.info "2 rooms"
        IO.inspect t, limit: :infinity
    end

    send :memo_mux, {:user, "plop", {:set, self(), {:rooms, "room", :del}}}
    send :memo_mux, {:user, "plop", {:set, self(), {:rooms, "another room", :del}}}

    send :memo_mux, {:user, "plop", {:get, self(), {:room_list}}}

    receive do
      t ->
        Logger.info "no rooms"
        IO.inspect t, limit: :infinity
    end
  end

  def set_get_has_new_test do
    create_user_get_user_test()
    send :memo_mux, {:user, "plop", {:set, self(), {:has_new, true}}}

    send :memo_mux, {:user, "plop", {:get, self(), {:has_new}}}

    receive do
      t ->
        IO.puts "should be true"
        IO.inspect t, limit: :infinity
    end

    send :memo_mux, {:user, "plop", {:set, self(), {:has_new, false}}}

    send :memo_mux, {:user, "plop", {:get, self(), {:has_new}}}

    receive do
      t ->
        IO.puts "should be false"
        IO.inspect t, limit: :infinity
    end
  end

  def full_user_json_test do
    user = %{
      :user_id => "plop",
      :notifs => [],
      :friends => [],
      :rooms => [],
      :has_new => false
    }

    friend_request = %{:friend_request => %{:from => "lolcat", :to => "doggo"}}
    room_invite = %{:room_invite => %{:room => [], :to => "doggo"}}

    send :memo_mux, {:user, "plop", {:create_user, user}}
    send :memo_mux, {:user, "plop", {:set, self(), {:notifs, friend_request, :add}}}
    send :memo_mux, {:user, "plop", {:set, self(), {:notifs, room_invite, :add}}}

    friend1 = %{:friend => %{:user_id => "user_id", :friends => [%{:user_id => "lolcat"}, %{:user_id => "doggo"}]}}
    friend2 = %{:friend => %{:user_id => "other_user_id", :friends => [%{:user_id => "lolcat"}, %{:user_id => "doggo"}]}}

    send :memo_mux, {:user, "plop", {:set, self(), {:friends, "user_id", friend1, :add}}}
    send :memo_mux, {:user, "plop", {:set, self(), {:friends, "other_user_id", friend2, :add}}}

    send :memo_mux, {:user, "plop", {:set, self(), {:rooms, "Kor-Nelzizandaaaaaa@room", :add}}}
    send :memo_mux, {:user, "plop", {:set, self(), {:rooms, "Kor-Nelzizandaaaaaa@another room", :add}}}

    create_rooms_full_user_test()

    {user_data, _} = get_upd("plop")

    user_data
  end

  defp get_upd(user_id) do
    send :memo_mux, {:user, user_id, {:get, self(), {:user}}}
    receive do
      {:error, error} -> Logger.info(error)
      user_data ->
        IO.inspect user_data
        {rooms, pics} = user_data.rooms |> Serv.get_all_rooms([], [])
        #Logger.info "1"
        user_data_rooms = user_data |> Map.replace!(:rooms, rooms)
        #Logger.info "2"
        user_data_rooms_json = Jason.encode!(user_data_rooms)
        #Logger.info "3"
        {user_data_rooms_json, pics}
    end
  end

  #################################
  ######     Room Tests     #######
  #################################

  def create_room_test do
    room_data = %{
    :owner => "Kor-Nelzizandaaaaaa",
    :name => "room",
    :topic => "Underground Bayblade Cabal",
    :icon => nil,
    :users => [],
    :quests => [],
    :quest_pics => []
    }

    send :memo_mux, {:room, "Kor-Nelzizandaaaaaa@room", {:add, room_data}}
    send :memo_mux, {:room, "Kor-Nelzizandaaaaaa@room", {:get, self(), {:room}}}

    receive do
      t ->
        IO.inspect t, [limit: :infinity, label: "A room"]
    end
  end

  def create_rooms_full_user_test do
    room_data = %{
    :owner => "Kor-Nelzizandaaaaaa",
    :name => "room",
    :topic => "Underground Bayblade Cabal",
    :icon => nil,
    :users => [],
    :quests => [],
    :quest_pics => []
    }

    send :memo_mux, {:room, "Kor-Nelzizandaaaaaa@room", {:add, room_data}}

    room_data = %{
    :owner => "Kor-Nelzizandaaaaaa",
    :name => "another room",
    :topic => "Underground Bayblade Cabal",
    :icon => nil,
    :users => [],
    :quests => [],
    :quest_pics => []
    }

    send :memo_mux, {:room, "Kor-Nelzizandaaaaaa@another room", {:add, room_data}}
  end
end
