defmodule Tests do
  def user_data_test do
    user = %{:user_id => "plop", :notifs => [], :friends => [], :rooms => [], :hasNew => false}
    send :memo_mux, {:user, "plop", {:create_user, user}}
    IO.puts "1"
    send :memo_mux, {:user, "plop", {:get, self(), {:user}}}
    IO.puts "2"
    receive do
      thing -> thing
    end
  end
end
