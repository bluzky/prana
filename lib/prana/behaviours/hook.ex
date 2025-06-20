defmodule Prana.Behaviour.Hook do
  @moduledoc """
  Behavior for event hooks in the system.
  Allows external systems to react to workflow events.
  """

  @type event :: atom()
  @type event_data :: map()

  @doc """
  Handle an event with the given data
  """
  @callback handle_event(event(), event_data()) :: :ok | {:error, reason :: any()}

  @doc """
  List events this hook is interested in
  """
  @callback interested_events() :: [event()]

  @optional_callbacks [interested_events: 0]
end
