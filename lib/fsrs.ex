defmodule ExFsrs do
  @moduledoc """
  Main module for the FSRS (Free Spaced Repetition System) implementation in Elixir.
  """

  @type t :: %__MODULE__{
    card_id: integer(),
    state: :learning | :review | :relearning,
    step: integer() | nil,
    stability: float() | nil,
    difficulty: float() | nil,
    due: DateTime.t(),
    last_review: DateTime.t() | nil
  }

  @type rating :: :again | :hard | :good | :easy
  @type state :: :learning | :review | :relearning

  defstruct [
    :card_id,
    :state,
    :step,
    :stability,
    :difficulty,
    :due,
    :last_review
  ]

  @doc """
  Creates a new card with default values.

  ## Parameters
    - opts: Keyword list of options
      - card_id: Unique identifier for the card
      - state: Current learning state (:learning, :review, or :relearning)
      - step: Current learning/relearning step
      - stability: Current stability value
      - difficulty: Current difficulty value
      - due: Due date for next review
      - last_review: Date of last review

  ## Returns
    - A new ExFsrs struct
  """
  def new(opts \\ []) do
    %__MODULE__{
      card_id: Keyword.get(opts, :card_id, System.system_time(:millisecond)),
      state: Keyword.get(opts, :state, :learning),
      step: Keyword.get(opts, :step, 0),
      stability: Keyword.get(opts, :stability, nil),
      difficulty: Keyword.get(opts, :difficulty, nil),
      due: Keyword.get(opts, :due, DateTime.utc_now()),
      last_review: Keyword.get(opts, :last_review, nil)
    }
  end

  @doc """
  Converts a card to a map for storage.

  ## Parameters
    - card: ExFsrs struct to convert

  ## Returns
    - Map representation of the card
  """
  def to_map(%__MODULE__{} = card) do
    %{
      "card_id" => card.card_id,
      "state" => card.state,
      "step" => card.step,
      "stability" => card.stability,
      "difficulty" => card.difficulty,
      "due" => DateTime.to_iso8601(card.due),
      "last_review" => if(card.last_review, do: DateTime.to_iso8601(card.last_review), else: nil)
    }
  end

  @doc """
  Creates a card from a map.

  ## Parameters
    - map: Map containing card data

  ## Returns
    - ExFsrs struct
  """
  def from_map(map) do
    due_date = map[:due] || map["due"]
    last_review = map[:last_review] || map["last_review"]
    state = (map[:state] || map["state"]) |> String.to_atom()

    %__MODULE__{
      card_id: map[:card_id] || map["card_id"],
      state: state,
      step: map[:step] || map["step"],
      stability: map[:stability] || map["stability"],
      difficulty: map[:difficulty] || map["difficulty"],
      due: case DateTime.from_iso8601(due_date) do
        {:ok, datetime, 0} -> datetime
        error ->
          raise "Invalid ISO8601 datetime format for due date: #{inspect(due_date)}"
      end,
      last_review: if last_review do
        case DateTime.from_iso8601(last_review) do
          {:ok, datetime, 0} -> datetime
          error ->
            raise "Invalid ISO8601 datetime format for last_review: #{inspect(last_review)}"
        end
      else
        nil
      end
    }
  end

  @doc """
  Calculates the retrievability of a card at a given time.

  ## Parameters
    - card: ExFsrs struct
    - current_datetime: Current datetime (defaults to UTC now)

  ## Returns
    - Float between 0 and 1 representing retrievability
  """
  def get_retrievability(card, current_datetime \\ DateTime.utc_now())
  def get_retrievability(%__MODULE__{last_review: nil}, _current_datetime), do: 0
  def get_retrievability(%__MODULE__{} = card, current_datetime) do
    days_since_last_review = max(0, DateTime.diff(current_datetime, card.last_review, :day))
    factor = :math.pow(0.9, 1 / -0.5) - 1
    decay = -0.5
    (1 + factor * days_since_last_review / card.stability) ** decay
  end

  @doc """
  Reviews a card using the FSRS algorithm.

  ## Parameters
    - card: ExFsrs struct to review
    - rating: Rating given to the card (:again, :hard, :good, or :easy)
    - review_datetime: DateTime of the review (defaults to current time)
    - review_duration: Duration of the review in milliseconds

  ## Returns
    - Tuple containing {updated_card, review_log}
  """
  def review_card(card, rating, review_datetime \\ DateTime.utc_now(), review_duration \\ nil) do
    scheduler = ExFsrs.Scheduler.new()
    ExFsrs.Scheduler.review_card(scheduler, card, rating, review_datetime, review_duration)
  end
end
