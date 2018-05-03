defmodule Tests do
  def create_user_get_user_test do
    user = %{
      :user_id => "plop",
      :notifs => [],
      :friends => [],
      :rooms => [],
      :hasNew => false
    }
    send :memo_mux, {:user, "plop", {:create_user, user}}
    send :memo_mux, {:user, "plop", {:get, self(), {:user}}}
    receive do
      thing -> thing
    end
  end

  def set_get_user_id_test do
    send :memo_mux, {:user, "plop", {:set, self(), {:user_id, "plip"}}}
    send :memo_mux, {:user, "plop", {:get, self(), {:user_id}}}
    receive do
      t -> t
    end
  end

  # :notifs => [
  # %{:friend_request => %{:from => lolcat, :to => doggo}},
  # %{:room_invite => %{:room => [], :to => lolcat}},
  # etc...
  # ]
  def set_get_notifs_test do
    friend_request = %{:friend_request => %{:from => "lolcat", :to => "doggo"}}
    room_invite = %{:room_invite => %{:room => [], :to => "doggo"}}

    send :memo_mux, {:user, "plop", {:set, self(), friend_request, {:notifs, :add}}}
    send :memo_mux, {:user, "plop", {:get, self(), {:notifs}}}

    receive do
      t ->
        IO.puts "notifs should have 1 notif"
        IO.inspect t, limit: :infinity
    end

    send :memo_mux, {:user, "plop", {:set, self(), {:notifs, room_invite, :add}}}
    send :memo_mux, {:user, "plop", {:get, self(), {:notifs}}}

    receive do
      t ->
        IO.puts "notifs should have 2 notifs"
        IO.inspect t, limit: :infinity
    end

    send :memo_mux, {:user, "plop", {:set, self(), {:notifs, friend_request, :del}}}
    send :memo_mux, {:user, "plop", {:set, self(), {:notifs, room_invite, :del}}}
    send :memo_mux, {:user, "plop", {:get, self(), {:notifs}}}

    receive do
      t ->
        IO.puts "notifs should be empty"
        IO.inspect t, limit: :infinity
    end
  end

  # :friends => [
  # {:friend, %{:user_id => user_id, :friends => []}},
  # etc...
  # ]
  def set_get_friends_test do
    friend1 = {:friend, %{:user_id => "user_id", :friends => [{:user_id, "lolcat"}, {:user_id, "doggo"}]}}
    friend2 = {:friend, %{:user_id => "other_user_id", :friends => [{:user_id, "lolcat"}, {:user_id, "doggo"}]}}

    send :memo_mux, {:user, "plop", {:set, self(), {:friends, "user_id", friend1, :add}}}
  end
end
