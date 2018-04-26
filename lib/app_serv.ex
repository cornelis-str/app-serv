
defmodule Serv do
  require Logger

  @doc """
  Starts accepting connections on the given 'port'.
  """
  def accept(port) do
    # http://erlang.org/doc/man/gen_tcp.html
    {:ok, socket} =
      :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true])

    Logger.info("Accepting connections on port #{port}")
    loop_acceptor(socket)
  end

  # Lyssnar efter anrop till port och startar process för behandling av input
  defp loop_acceptor(socket) do
    # Vänntar på anslutning
    {:ok, client} = :gen_tcp.accept(socket)

    # Startar process för att behandla anslutning
    {:ok, pid} = Task.Supervisor.start_child(Serv.TaskSupervisor, fn -> serve(client) end)
    :ok = :gen_tcp.controlling_process(client, pid)

    # Loopar funktionen
    loop_acceptor(socket)
  end

  """
  läser från klient och skickar till parse eller fel till log
  """
  defp serve(socket) do
    case read_line(socket) do
      {:error, error} -> Logger.info("serve: #{error}")
      mess ->
        #parse(mess, socket)
        write_line(mess, socket)
        write_line("\r\n", socket)
        "echoed" |> Logger.info()
        serve(socket)
    end
  end

  @doc """
  Tar in förfrågan och skickarvidare info baserad på denna
  """
  def parse(mess, socket) do
    # Gör lista av sträng
    [h | tail] = String.split(mess, " ")
    case h do
      # Skickar vidare info och startar process om POS request
      "POS" -> spawn fn -> pos_req(tail) end

      # Skickar vidare info och startar process om PUT request
      "PUT" ->
        # PUT requests kan vara av olika typ vanlig och PIC
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
            pic_mess |> Enum.reverse() # |> send_mess(socket) TODO Byt ut mot spara till memo
            Logger.info("pic sent")

          _ ->
            IO.inspect tail, limit: :infinity
            spawn fn -> Enum.join(tail, " ") |> put_req(socket) end
        end

      # Skickar vidare info och startar process om DEL request
      "DEL" -> spawn fn -> del_req(tail) end

      # Skickar vidare info och startar process om PUT request
      "GET" -> spawn fn -> get_req(tail) end
    end
  end

  # TODO
  # Ta hand om POS requests
  defp pos_req(_) do end


  # Läser in len stor bild i 1024 bytes bitar
  defp pic_req(mem, 0, _), do: mem
  defp pic_req(mem, len, socket) do
    cond do
      len > 1024 ->
        [read_bytes(socket, 1024) | mem]
        |> pic_req(len - 1024, socket)
      # Nedan går endast igång om inget ovan gått igång
      true ->
        Logger.info(len)
        [read_bytes(socket, len) | mem]
        |> pic_req(0, socket)
    end
  end

  # TODO
  # Ska ta hand om PUT requests som != PIC
  defp put_req(json, socket) do
    #IO.inspect json
    write_line("#{json}\r\n\r\n", socket)
    Logger.info("Sent mess")
  end

  # TODO
  # Ska ta hand om DEL requests
  defp del_req(_) do end

  # TODO
  # Ska ta hand om GET requests
  defp get_req(_) do end


  # Läser bytes antal bytes från socker
  defp read_bytes(socket, bytes) do
    case :gen_tcp.recv(socket, bytes) do
      {:ok, data} -> data
      {:error, closed} -> {:error, closed}
    end
  end

  # Läser oändligt (not really) långa meddelanden från socket
  defp read_line(socket) do
    case :gen_tcp.recv(socket, 0) do #How this know where to stop is magic.
      {:ok, data} -> data
      {:error, closed} -> {:error, closed}
    end
  end

  # TODO InProgress
  # Skickar data från lista till socket
  defp send_mess([], socket), do: write_line("\r\n", socket)
  defp send_mess([h|t], socket) do
    case write_line(h, socket) do
      :ok ->  send_mess(t, socket)
      {:error, error} -> Logger.info("send_mess: #{error}")
    end
  end

  # Skickar medelande till socket
  defp write_line(line, socket) do
    case :gen_tcp.send(socket, line) do
      {:error, error} -> {:error, error}
      _ -> :ok
    end
  end
end
