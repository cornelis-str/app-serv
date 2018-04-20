
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
                                              fn -> serve(client, print_pid) end)
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

  def parse(mess, socket) do
    [h | tail] = String.split(mess, " ")
    case h do
      "POS" -> spawn fn -> pos_req(tail) end
      "PUT" ->
        case tail do
          ["PIC"|t] ->
            IO.inspect t, limit: :infinity

            # send ok
            write_line("ok\r\n", socket)
            Logger.info("ok sent")

            # Get pic
            pic_mess = pic_req([], List.first(t) |> String.to_integer(), socket)
            Logger.info("got pic")
            Logger.info(Enum.count(pic_mess))

            # send ok
            write_line("ok\r\n", socket)
            Logger.info("ok2 sent")

            # send pic
            pic_mess |> Enum.reverse() |> send_mess(socket)
            Logger.info("pic sent")

          _ ->
            IO.inspect tail, limit: :infinity
            spawn fn -> put_req(Enum.join(tail, " "), socket) end
        end
      "DEL" -> spawn fn -> del_req(tail) end
      "GET" -> spawn fn -> get_req(tail) end
    end
  end

  defp pos_req(json) do end

  defp pic_req(mem, 0, _), do: mem
  defp pic_req(mem, len, socket) do
    cond do
      len > 1024 ->
        [read_bytes(socket, 1024) | mem]
        |> pic_req(len - 1024, socket)
      true ->
        Logger.info(len)
        [read_bytes(socket, len) | mem]
        |> pic_req(0, socket)
    end
  end

  defp put_req(json, socket) do
    IO.inspect json
    write_line("#{json}\r\n\r\n", socket)
    Logger.info("Sent mess")
  end

  defp del_req(json) do end
  defp get_req(json) do end

  defp read_bytes(socket, bytes) do
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
  end

  defp send_mess([], _), do: :ok #write_line("\r\n", socket)
  defp send_mess([h|t], socket) do
    case write_line(h, socket) do
      :ok ->  send_mess(t, socket)
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
