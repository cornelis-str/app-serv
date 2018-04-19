
defmodule Serv do
  require Logger

  @doc """
  Starts accepting connections on the given 'port'.
  """
  def accept(port) do
    # http://erlang.org/doc/man/gen_tcp.html
    {:ok, socket} =
      :gen_tcp.listen(port, [:binary, packet: 0, active: false, reuseaddr: true])

    Logger.info("Accepting connections on port #{port}")
    insPID = Process.spawn(fn ->
      IO.inspect
    end)
    loop_acceptor(socket, insPID)
  end

  defp loop_acceptor(socket, insPID) do
    {:ok, client} = :gen_tcp.accept(socket)
    {:ok, pid} = Task.Supervisor.start_child(Serv.TaskSupervisor, fn -> serve(client, [], insPID) end)
    :ok = :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket, insPID)
  end

  defp serve(socket, mem, insPID) do
    case read_line(socket) do
      {:error, error} -> Logger.info("serve: #{error}")
      mess -> mess_handler(mess, mem, socket, insPID)
    end
  end

  defp read_line(socket) do
    case :gen_tcp.recv(socket, 0, 10000) do
      {:ok, data} -> data
      {:error, closed} -> {:error, closed}
    end
  end

  defp write_line(line, socket) do
    case :gen_tcp.send(socket, line) do
      {:error, error} -> {:error, error}
      _ -> :ok
    end
  end

  defp send_mess(socket, []), do: write_line("\r\n", socket)
  defp send_mess(socket, [h|t]) do
    case write_line(h, socket) do
      :ok ->  send_mess(socket, t)
      {:error, error} -> Logger.info("send_mess: #{error}")
    end
  end

  defp mess_handler(mess, mem, socket, inspPID) do
    case mess do
      "\r\n" ->
        Logger.info("sending")
        send_mess(socket, Enum.reverse(mem))
        Logger.info("Data sent")
      _ ->
        #IO.inspect(mess, limit: :infinity)
        send
        serve(socket, [mess | mem])
      end
  end

  defp inspector do
    receive do
      {:msg, contents} -> IO.inspect(contents, limit: :infinity)
    end
  end
end
