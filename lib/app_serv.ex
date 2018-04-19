
defmodule Serv do
  require Logger

  @doc """
  Starts accepting connections on the given 'port'.
  """
  def accept(port) do
    # http://erlang.org/doc/man/gen_tcp.html
    {:ok, socket} =
      :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true])

    print_pid = spawn fn -> logPrint() end
    Logger.info("Accepting connections on port #{port}")
    loop_acceptor(socket, print_pid)
  end

  defp loop_acceptor(socket, print_pid) do
    {:ok, client} = :gen_tcp.accept(socket)
    {:ok, pid} = Task.Supervisor.start_child(Serv.TaskSupervisor,
                                              fn -> serve(client, [], print_pid) end)
    :ok = :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket, print_pid)
  end

  defp serve(socket, mem, print_pid) do
    case read_line(socket) do
      {:error, error} -> Logger.info("serve: #{error}")
      mess -> mess_handler(mess, mem, socket, print_pid)
    end
  end

  defp read_line(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} -> data
      {:error, closed} -> {:error, closed}
    end
  end
  """
  defp mess_handler(mess, [], socket, print_pid) do
    send(print_pid, {:msg, inspect(mess, limit: :infinity)})
    serve(socket, mess, print_pid)
  end
"""
  defp mess_handler(mess, mem, socket, print_pid) do
    """
    cond do
      h <> mess == "\r\n" ->
        send(print_pid, {:msg, inspect(mess, limit: :infinity)})
        Logger.info("sending")
        send_mess(socket, Enum.reverse(mem))
        Logger.info("Data sent")
      true ->
        send(print_pid, {:msg, inspect(mess, limit: :infinity)})
        serve(socket, [mess | mem], print_pid)
    end
    """
    if mess == "\r\n" do
      send(print_pid, {:msg, inspect(mess, limit: :infinity)})
      Logger.info("sending")
      send_mess(socket, Enum.reverse(mem))
      Logger.info("Data sent")
    else
      send(print_pid, {:msg, inspect(mess, limit: :infinity)})
      serve(socket, [mess | mem], print_pid)
    end

  end

  defp cflf_finder([h|t], {a,b}) do
    case {a,b,h} do
      {125,13,10} -> {:msg, :end}
      _ -> cflf_finder(t, {b,h})
    end
  end

  defp send_mess(socket, []), do: write_line("\r\n", socket)
  defp send_mess(socket, [h|t]) do
    case write_line(h, socket) do
      :ok ->  send_mess(socket, t)
      {:error, error} -> Logger.info("send_mess: #{error}")
    end
  end

  defp write_line(line, socket) do
    case :gen_tcp.send(socket, line) do
      {:error, error} -> {:error, error}
      _ -> :ok
    end
  end

  def logPrint do
    receive do
      {:msg, cont} -> IO.puts cont
      logPrint()
    end
  end
end
