
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

  defp serve(socket, print_pid) do
    case read_line(socket) do
      {:error, error} -> Logger.info("serve: #{error}")
      mess ->
        parse(mess, socket)
        serve(socket, print_pid)
    end
  end

  defp parse(<<method::size(24), tail::binary>>, socket) do
    case method do
      "POS" ->
        <<imethod::size(24), tailier::binary>> = tail
        case imethod do
          "PIC" -> pic_req([], tailier, socket)
          _ -> spawn fn -> pos_req(tail) end
        end
      "PUT" -> spawn fn -> put_req(tail) end
      "DEL" -> spawn fn -> del_req(tail) end
      "GET" -> spawn fn -> get_req(tail) end
    end
  end

  defp pic_req(mem, 0, _), do: mem
  defp pic_req(mem, len, socket) do
    cond do
      len > 1024 ->
        [read_bytes(1024, socket) | mem]
        |> pic_req(len - 1024, socket)
      true ->
        [read_bytes(len, socket) | mem]
        |> pic_req(0, socket)
    end
  end

  defp read_bytes(bytes, socket) do
    case :gen_tcp.recv(socket, bytes) do
      {:ok, data} -> data
      {:error, closed} -> {:error, closed}
    end
  end

  defp read_line(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} -> data
      {:error, closed} -> {:error, closed}
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
end
