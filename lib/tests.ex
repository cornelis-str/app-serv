defmodule Tests do
  def user_data_test do
    send :memo_mux, {:user, {"plop", {:create_user, {:get, self(), {:user_id}}}}}
  end
end
