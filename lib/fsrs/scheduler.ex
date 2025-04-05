defmodule ExFsrs.Scheduler do
  @moduledoc """
  FSRS Scheduler implementation in Elixir.
  Handles the core spaced repetition algorithm.
  """

  alias ExFsrs

  @learning_steps [60.0, 600.0]  # 1 minuta, 10 minut
  @relearning_steps [600.0]  # 10 minut
  @maximum_interval 36500
  @default_parameters [
    0.40255,  # initial stability for again
    1.18385,  # initial stability for hard
    3.173,    # initial stability for good
    15.69105, # initial stability for easy
    7.1949,   # initial difficulty
    0.5345,   # difficulty decay
    1.4604,   # difficulty factor
    0.0046,   # mean reversion
    1.54575,  # stability decay
    0.1192,   # stability factor
    1.01925,  # stability growth
    1.9395,   # forget stability
    0.11,     # forget difficulty
    0.29605,  # forget growth
    2.2698,   # forget penalty
    0.2315,   # hard penalty
    2.9898,   # easy bonus
    0.51655,  # short term stability
    0.6621    # short term decay
  ]

  @type t :: %__MODULE__{
    parameters: [float()],
    desired_retention: float(),
    learning_steps: [float()],
    relearning_steps: [float()],
    maximum_interval: integer(),
    enable_fuzzing: boolean(),
    default_parameters: [float()]
  }

  defstruct parameters: @default_parameters,
            desired_retention: 0.9,
            learning_steps: @learning_steps,
            relearning_steps: @relearning_steps,
            maximum_interval: @maximum_interval,
            enable_fuzzing: true,
            default_parameters: @default_parameters

  @decay -0.5
  @factor :math.pow(0.9, 1 / @decay) - 1

  @fuzz_ranges [
    %{
      start: 2.5,
      end: 7.0,
      factor: 0.15
    },
    %{
      start: 7.0,
      end: 20.0,
      factor: 0.1
    },
    %{
      start: 20.0,
      end: :infinity,
      factor: 0.05
    }
  ]

  @doc """
  Creates a new scheduler with default parameters.

  ## Parameters
    - opts: Keyword list of options
      - parameters: List of 19 model weights
      - desired_retention: Target retention rate (default: 0.9)
      - learning_steps: List of time intervals for learning state
      - relearning_steps: List of time intervals for relearning state
      - maximum_interval: Maximum days for future scheduling
      - enable_fuzzing: Whether to apply random intervals

  ## Returns
    - A new Scheduler struct
  """
  def new(opts \\ []) do
    parameters = Keyword.get(opts, :parameters, @default_parameters)
    desired_retention = Keyword.get(opts, :desired_retention, 0.9)
    learning_steps = Keyword.get(opts, :learning_steps, @learning_steps)
    relearning_steps = Keyword.get(opts, :relearning_steps, @relearning_steps)
    maximum_interval = Keyword.get(opts, :maximum_interval, @maximum_interval)
    enable_fuzzing = Keyword.get(opts, :enable_fuzzing, true)

    %__MODULE__{
      parameters: parameters,
      desired_retention: desired_retention,
      learning_steps: learning_steps,
      relearning_steps: relearning_steps,
      maximum_interval: maximum_interval,
      enable_fuzzing: enable_fuzzing,
      default_parameters: parameters
    }
  end

  @doc """
  Reviews a card and returns the updated card and review log.

  ## Parameters
    - scheduler: Scheduler struct
    - card: ExFsrs struct to review
    - rating: Rating given to the card
    - review_datetime: DateTime of the review
    - review_duration: Duration of the review in milliseconds

  ## Returns
    - Tuple containing {updated_card, review_log}
  """
  def review_card(
    %__MODULE__{} = scheduler,
    %ExFsrs{} = card,
    rating,
    review_datetime \\ DateTime.utc_now(),
    review_duration \\ nil
  ) do
    # Calculate days since last review
    days_since_last_review = case card.last_review do
      nil -> nil
      last_review -> DateTime.diff(review_datetime, last_review, :day)
    end

    # Update card based on state
    updated_card = case card.state do
      :learning -> update_learning_card(card, rating, review_datetime, scheduler)
      :review -> update_review_card(card, rating, review_datetime, scheduler)
      :relearning -> update_relearning_card(card, rating, review_datetime, scheduler)
    end

    # Create review log
    review_log = %{
      card: updated_card,
      rating: rating,
      review_datetime: review_datetime,
      review_duration: review_duration
    }

    {updated_card, review_log}
  end

  # Helper functions for FSRS algorithm
  defp update_learning_card(card, rating, review_datetime, scheduler) do
    {stability, difficulty} = cond do
      is_nil(card.stability) and is_nil(card.difficulty) ->
        {initial_stability(rating, scheduler), initial_difficulty(rating, scheduler)}

      days_since_last_review(card, review_datetime) < 1 ->
        {short_term_stability(card.stability, rating, scheduler),
         next_difficulty(card.difficulty, rating, scheduler)}

      true ->
        {next_stability(card.difficulty, card.stability, get_retrievability(card, review_datetime), rating, scheduler),
         next_difficulty(card.difficulty, rating, scheduler)}
    end

    {next_state, next_step, next_interval} = case rating do
      :again ->
        if card.step + 1 == length(scheduler.learning_steps) do
          {:review, nil, next_interval(stability, scheduler)}
        else
          {:learning, 0, Enum.at(scheduler.learning_steps, 0, 60)}
        end

      :hard ->
        interval = cond do
          card.step == 0 and length(scheduler.learning_steps) == 1 ->
            Enum.at(scheduler.learning_steps, 0, 60) * 1.5
          card.step == 0 and length(scheduler.learning_steps) >= 2 ->
            (Enum.at(scheduler.learning_steps, 0, 60) + Enum.at(scheduler.learning_steps, 1, 600)) / 2.0
          true ->
            Enum.at(scheduler.learning_steps, card.step, 600)
        end
        {:learning, card.step, interval}

      :good ->
        if card.step + 1 == length(scheduler.learning_steps) do
          {:review, nil, next_interval(stability, scheduler)}
        else
          {:learning, card.step + 1, Enum.at(scheduler.learning_steps, card.step + 1, 600)}
        end

      :easy ->
        {:review, nil, next_interval(stability, scheduler)}
    end

    next_interval = if scheduler.enable_fuzzing and next_state == :review do
      get_fuzzed_interval(next_interval)
    else
      next_interval
    end

    %{card |
      state: next_state,
      step: next_step,
      stability: stability,
      difficulty: difficulty,
      due: DateTime.add(review_datetime, round(next_interval), :minute),
      last_review: review_datetime
    }
  end

  defp update_review_card(card, rating, review_datetime, scheduler) do
    {stability, difficulty} = cond do
      days_since_last_review(card, review_datetime) < 1 ->
        {short_term_stability(card.stability, rating, scheduler),
         next_difficulty(card.difficulty, rating, scheduler)}

      true ->
        {next_stability(card.difficulty, card.stability, get_retrievability(card, review_datetime), rating, scheduler),
         next_difficulty(card.difficulty, rating, scheduler)}
    end

    {next_state, next_step, next_interval} = case rating do
      :again ->
        if length(scheduler.relearning_steps) == 0 do
          {:review, nil, next_interval(stability, scheduler)}
        else
          {:relearning, 0, Enum.at(scheduler.relearning_steps, 0)}
        end

      _ ->
        {:review, nil, next_interval(stability, scheduler)}
    end

    next_interval = if scheduler.enable_fuzzing and next_state == :review do
      get_fuzzed_interval(next_interval)
    else
      next_interval
    end

    %{card |
      state: next_state,
      step: next_step,
      stability: stability,
      difficulty: difficulty,
      due: DateTime.add(review_datetime, round(next_interval), :minute),
      last_review: review_datetime
    }
  end

  defp update_relearning_card(card, rating, review_datetime, scheduler) do
    {stability, difficulty} = cond do
      days_since_last_review(card, review_datetime) < 1 ->
        {short_term_stability(card.stability, rating, scheduler),
         next_difficulty(card.difficulty, rating, scheduler)}

      true ->
        {next_stability(card.difficulty, card.stability, get_retrievability(card, review_datetime), rating, scheduler),
         next_difficulty(card.difficulty, rating, scheduler)}
    end

    {next_state, next_step, next_interval} = case rating do
      :again ->
        if card.step + 1 == length(scheduler.relearning_steps) do
          {:review, nil, next_interval(stability, scheduler)}
        else
          {:relearning, 0, Enum.at(scheduler.relearning_steps, 0, 600)}
        end

      :hard ->
        interval = cond do
          card.step == 0 and length(scheduler.relearning_steps) == 1 ->
            Enum.at(scheduler.relearning_steps, 0, 600) * 1.5
          card.step == 0 and length(scheduler.relearning_steps) >= 2 ->
            (Enum.at(scheduler.relearning_steps, 0, 600) + Enum.at(scheduler.relearning_steps, 1, 1200)) / 2.0
          true ->
            Enum.at(scheduler.relearning_steps, card.step, 600)
        end
        {:relearning, card.step, interval}

      :good ->
        if card.step + 1 == length(scheduler.relearning_steps) do
          {:review, nil, next_interval(stability, scheduler)}
        else
          {:relearning, card.step + 1, Enum.at(scheduler.relearning_steps, card.step + 1, 600)}
        end

      :easy ->
        {:review, nil, next_interval(stability, scheduler)}
    end

    next_interval = if scheduler.enable_fuzzing and next_state == :review do
      get_fuzzed_interval(next_interval)
    else
      next_interval
    end

    %{card |
      state: next_state,
      step: next_step,
      stability: stability,
      difficulty: difficulty,
      due: DateTime.add(review_datetime, round(next_interval), :minute),
      last_review: review_datetime
    }
  end

  def next_interval(stability, scheduler) do
    factor = :math.pow(0.9, 1 / @decay) - 1
    next_interval = (stability / factor) * (:math.pow(scheduler.desired_retention, 1 / @decay) - 1)
    next_interval = round(next_interval)  # intervals are full days
    next_interval = max(next_interval, 1)  # must be at least 1 day long
    next_interval = min(next_interval, scheduler.maximum_interval)  # can not be longer than the maximum interval
    next_interval * 24 * 60  # převod dnů na minuty
  end

  def get_fuzzed_interval(interval) do
    {min_ivl, max_ivl} = get_fuzz_range(interval)
    fuzzed = min_ivl + (:rand.uniform() * (max_ivl - min_ivl + 1))
    round(fuzzed)
  end

  defp get_fuzz_range(interval_days) do
    cond do
      interval_days < 2.5 -> {interval_days, interval_days}
      interval_days < 7.0 ->
        delta = round(interval_days * 0.15)
        {max(2, interval_days - delta), min(interval_days + delta, 36500)}
      interval_days < 20.0 ->
        delta = round(interval_days * 0.1)
        {max(2, interval_days - delta), min(interval_days + delta, 36500)}
      true ->
        delta = round(interval_days * 0.05)
        {max(2, interval_days - delta), min(interval_days + delta, 36500)}
    end
  end

  defp initial_stability(rating, _scheduler) do
    case rating do
      :again -> 0.40255
      :hard -> 1.18385
      :good -> 3.173
      :easy -> 15.69105
    end

  end

  defp initial_difficulty(rating, _scheduler) do
    case rating do
      :again -> 7.1949
      :hard -> 6.488305268471453
      :good -> 5.282434422319005
      :easy -> 3.2245015893713678
    end
  end

  def next_stability(difficulty, stability, retrievability, rating, scheduler) do
    case rating do
      :again -> next_forget_stability(difficulty, stability, retrievability, scheduler)
      _ -> next_recall_stability(difficulty, stability, retrievability, rating, scheduler)
    end
  end

  defp next_forget_stability(difficulty, stability, retrievability, scheduler) do
    parametr11 = Enum.at(scheduler.parameters, 11)  # 1.9395
    parametr12 = Enum.at(scheduler.parameters, 12)  # 0.11
    parametr13 = Enum.at(scheduler.parameters, 13)  # 0.29605
    parametr14 = Enum.at(scheduler.parameters, 14)  # 2.2698
    parametr17 = Enum.at(scheduler.parameters, 17)  # 0.51655
    parametr18 = Enum.at(scheduler.parameters, 18)  # 0.6621

    # Long term calculation
    long_term = (
      parametr11 *  # 1.9395
      :math.pow(difficulty, -parametr12) *  # difficulty ** -0.11
      (:math.pow(stability + 1, parametr13) - 1) *  # ((stability + 1) ** 0.29605) - 1
      :math.exp((1 - retrievability) * parametr14)  # e ** ((1 - retrievability) * 2.2698)
    )

    # Short term calculation
    short_term = stability / :math.exp(parametr17 * parametr18)

    # Final result
    min(long_term, short_term)
  end

  defp next_recall_stability(difficulty, stability, retrievability, rating, scheduler) do
    parametr8 = Enum.at(scheduler.parameters, 8)    # 1.54575
    parametr9 = Enum.at(scheduler.parameters, 9)    # 0.1192
    parametr10 = Enum.at(scheduler.parameters, 10)  # 1.01925
    parametr15 = Enum.at(scheduler.parameters, 15)  # 0.2315
    parametr16 = Enum.at(scheduler.parameters, 16)  # 2.9898

    hard_penalty = if rating == :hard, do: parametr15, else: 1.0
    easy_bonus = if rating == :easy, do: parametr16, else: 1.0

    result = stability * (
      1 +
      :math.exp(parametr8) *  # e ** parameters[8]
      (11 - difficulty) *
      :math.pow(stability, -parametr9) *  # stability ** -parameters[9]
      (:math.exp((1 - retrievability) * parametr10) - 1) *  # (e ** ((1 - retrievability) * parameters[10])) - 1
      hard_penalty *
      easy_bonus
    )

    result
  end

  defp next_difficulty(difficulty, rating, scheduler) do
    difficulty = difficulty || 1.0

    # Linear damping function
    linear_damping = fn delta_difficulty, diff ->
      (10.0 - diff) * delta_difficulty / 9.0
    end

    # Mean reversion function
    parametr7 = Enum.at(scheduler.parameters, 7)  # 0.0046
    mean_reversion = fn arg1, arg2 ->
      parametr7 * arg1 + (1 - parametr7) * arg2
    end

    arg1 = initial_difficulty(:easy, scheduler)
    parametr6 = Enum.at(scheduler.parameters, 6)  # 1.4604
    delta_difficulty = -(parametr6 * (rating_to_number(rating) - 3))
    arg2 = difficulty + linear_damping.(delta_difficulty, difficulty)
    next_difficulty = mean_reversion.(arg1, arg2)

    # Bound next_difficulty between 1 and 10
    min(max(next_difficulty, 1.0), 10.0)
  end

  defp short_term_stability(stability, rating, scheduler) do
    parametr17 = Enum.at(scheduler.parameters, 17)  # 0.51655
    parametr18 = Enum.at(scheduler.parameters, 18)  # 0.6621
    stability * :math.exp(parametr17 * (rating_to_number(rating) - 3 + parametr18))
  end

  defp rating_to_number(rating) do
    case rating do
      :again -> 1
      :hard -> 2
      :good -> 3
      :easy -> 4
    end
  end

  defp days_since_last_review(card, review_datetime) do
    case card.last_review do
      nil -> nil
      last_review -> DateTime.diff(review_datetime, last_review, :day)
    end
  end

  defp get_retrievability(card, review_datetime) do
    case card.last_review do
      nil -> 0
      last_review ->
        elapsed_days = max(0, DateTime.diff(review_datetime, last_review, :day))
        :math.pow(1 + @factor * elapsed_days / card.stability, @decay)
    end
  end
end
