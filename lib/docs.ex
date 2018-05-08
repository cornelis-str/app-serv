defmodule Docs do
  # Can be found under docs/Docs.html
  # Generate new by running `mix docs` in project root

  @moduledoc """
    Dokumentering av datastrukturer och meddelandesyntax.

  # Datastrukturer:

  ## Datastruktur i Memo_user:
        user_data = %{
        :user_id => user_id,
        :notifs => [
          %{:friend_request => %{:from => user_id, :to => user_id_0}},
          %{:room_invite => %{:room_id => room_id, :to => user_id}},
          %{:submitted => %{:from => user_id, :to => user_id, :quest_id},
            :pic => <<ByteArray>> | nil,
            :string => str|nil
          },
          etc...
        ],
        :friends => [
          %{:friend => %{:user_id => user_id, :friends => [
              %{:user_id => user_id},
              %{:user_id => user_id}
              ]
            }
          },
          etc...],
        :rooms => [
          %{:room_id => room_id},
          etc...],
        :has_new => false | true
        }

  ## Versionen av user_data som skickas tillbaks till klienten:
        user_data_update = %{
        :user_id => lolcat,
        :notifs => [
            %{:friend_request => %{:from => lolcat, :to => doggo}},
            %{:room_invite => %{:room => [], :to => lolcat}},
            %{:submitted => %{:from => user_id, :to => user_id, :quest_id},
              :pic => <<ByteArray>> | nil,
              :string => str|nil
            },
          etc...
        ],
        :friends => [%{:friend => %{:user_id => user_id, :friends => []}}, etc...],
        :rooms => [%{:room_id => room_id, :room => room_data}, etc...],
        }

  ## Datastruktur i Memo_room:
        room_data = %{
        :owner => user_id,
        :name => room_name,
        :topic => topic,
        :icon => <<ByteArray>>,
        :users => [
            %{:user => user_id},
            etc...],
        :quests => [%{:quest_id => quest_id, :quest => JsonString}],
        :quest_pics => [%{:quest_pic_id => quest_pic_id, :pic => <<ByteArray>>}]
        }


  # Meddelande format för memo_mux:


  ## Användarmeddelanden


  ### Skapa användare:
      send :memo_mux, {:user, user_id, {:create_user, user_data}}

  ### Hämta användare:
      send :memo_mux, {:user, user_id, {:get, pid_of_sender, {:user}}}

  ### Ändra username:
      send :memo_mux, {:user, user_id, {:set, pid_of_sender, {:user_id, new_username}}}

  ### Hämta username:
      send :memo_mux, {:user, user_id, {:get, pid_of_sender, {:user_id}}}

  ### Skapa notifikation:
      send :memo_mux, {:user, user_id, {:set, pid_of_sender, {:notifs, notif, :add}}}

  #### Notifikations (notif) typer
  ##### Friend Request:
        %{:friend_request => %{:from => user_id_0, :to => user_id_1}}

  ##### Room Invite:
        %{:room_invite => %{:room_id => room_id, :to => user_id}}

  ##### Quest Submission:
        %{
        :submitted => %{:from => user_id_0, :to => user_id_1, :quest_id => quest_id},
        :pic => <<ByteArray>>,
        :string => string
        }

  ##### Quest Accepted:
        %{:accepted => %{:quest_id => quest_id}}

  ### Ta bort notifikation:
  I :submitted kan man sätta :pic och :string till nil då dessa inte tittas på för indentifiering av notifikationen.
      send :memo_mux, {:user, user_id, {:set, pid_of_sender, {:notifs, notif, :del}}}

  ### Hämta alla notifikationer:
      send :memo_mux, {:user, user_id, {:set, pid_of_sender, {:notifs}}}

  ### Lägg till en vän:
      send :memo_mux, {:user, user_id, {:set, pid_of_sender, {:friend, friends_user_id, friend_data, :add}}}

  #### Friend data
        %{:friend, %{
          :user_id => friends_user_id,
          :friends => [
            %{:user_id => user_id}
            ]
          }
        }

  ### Ta bort en vän:
      send :memo_mux, {:user, user_id, {:set, pid_of_sender, {:friend, friends_user_id, :del}}}

  ### Hämta en vän:
      send :memo_mux, {:user, user_id, {:get, pid_of_sender, {:friend, friends_user_id}}}

  ### Hämta vänlista:
      send :memo_mux, {:user, user_id, {:get, pid_of_sender, {:friends}}}

  ### Lägg till rum hos användare:
      send :memo_mux, {:user, user_id, {:set, pid_of_sender, {:room, room_id, :add}}}

  ### Ta bort rum från användare:
      send :memo_mux, {:user, user_id, {:set, pid_of_sender, {:room, room_id, :del}}}

  ### Hämta rumlista från användare:
      send :memo_mux, {:user, user_id, {:get, pid_of_sender, {:room_list}}}

  ### Sätt has_new
      send :memo_mux, {:user, user_id, {:set, pid_of_sender, {:has_new, true_or_false}}}

  ### Hämta has_new
      send :memo_mux, {:user, user_id, {:get, pid_of_sender, {:has_new}}}

  ## Rum meddelanden

  #### Rumdelar
      :owner = user_id,
      :name = name,
      :topic = topic,
      :icon = <<ByteArray>>,
      :users = [],
      :quests = [],
      :quest_pics = []

  ### Lägg till rum:
    Rum genereras om inget finns när ett försök att ändra något i det görs.

  ### Radera ett rum:
      send :memo_mux, {:room, room_id, {:set, pid_of_sender, {:room, room_id, :del}}}

  ### Hämta rum:
      send :memo_mux, {:room, room_id, {:get, pid_of_sender, {:room}}}

  ### Lägg till del av rum:
      send :memo_mux, {:room, room_id, {:set, pid_of_sender, {:room, room_part_type, room_part, :add}}}

  ### Ta bort del från rum:
      send :memo_mux, {:room, room_id, {:set, pid_of_sender, {:room, room_part_type, room_part, :del}}}

  ### Hämta del av rum:
      send :memo_mux, {:room, room_id, {:get, pid_of_sender, {:room, room_part}}}

  ### Lägg till quest:
      send :memo_mux, {:room, room_id, {:set, pid_of_sender, {:quest, quest_id, quest, :add}}}

  ### Ta bort quest:
      send :memo_mux, {:room, room_id, {:set, pid_of_sender, {:quest, quest_id, quest, :del}}}

  ### Hämta quest:
      send :memo_mux, {:room, room_id, {:get, pid_of_sender, {:quest, quest_id}}}

  ### Lägg till quest bild:
      send :memo_mux, {:room, room_id, {:set, pid_of_sender, {:quest_pic, resource_id, bild, :add}}}

  ### Ta bort quest bild:
      send :memo_mux, {:room, room_id, {:get, pid_of_sender, {:quest_pic, resource_id, bild, :del}}}

  ### Hämta quest bild:
      send :memo_mux, {:room, room_id, {:get, pid_of_sender, {:quest_pic, resource_id}}}
  """
end
