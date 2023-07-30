defmodule Parameters do
  defstruct request_retention: 0.9,
            maximum_interval: 36_500,
            weights:
              {0.4, 0.6, 2.4, 5.8, 4.93, 0.94, 0.86, 0.01, 1.49, 0.14, 0.94, 2.18, 0.05, 0.34,
               1.26, 0.29, 2.61}
end

defmodule Card do
  defstruct due: DateTime.utc_now(),
            stability: 0,
            difficulty: 0,
            elapsed_days: 0,
            scheduled_days: 0,
            reps: 0,
            lapses: 0,
            state: :new,
            last_review: DateTime.utc_now()

  def get_retrievability(%Card{state: :review} = card, now) do
    elapsed_days = max(0, DateTime.diff(now, card.last_review, :day))
    (1 + elapsed_days / (9 * card.stability)) ** -1
  end
end

defmodule ReviewLog do
  defstruct [
    :rating,
    :elapsed_days,
    :scheduled_days,
    :review,
    :state
  ]
end

defmodule SchedulingInfo do
  defstruct [
    :card,
    :review_log
  ]
end

defmodule SchedulingCards do
  defstruct [
    :again,
    :hard,
    :good,
    :easy
  ]

  def update_state(scheduling_cards, :new) do
    s = put_in(scheduling_cards.again.state, :learning)
    s = update_in(s.again.lapses, &(&1 + 1))
    s = put_in(s.hard.state, :learning)
    s = put_in(s.good.state, :learning)
    put_in(s.easy.state, :review)
  end

  def update_state(scheduling_cards, :review) do
    s = put_in(scheduling_cards.again.state, :relearning)
    s = update_in(s.again.lapses, &(&1 + 1))
    s = put_in(s.hard.state, :review)
    s = put_in(s.good.state, :review)
    put_in(s.easy.state, :review)
  end

  def update_state(scheduling_cards, state) do
    s = put_in(scheduling_cards.again.state, state)
    s = put_in(s.hard.state, state)
    s = put_in(s.good.state, :review)
    put_in(s.easy.state, :review)
  end

  def schedule(scheduling_cards, now, hard_interval, good_interval, easy_interval) do
    hard_due =
      if hard_interval > 0 do
        DateTime.add(now, hard_interval, :day)
      else
        DateTime.add(now, 10, :minute)
      end

    %SchedulingCards{
      scheduling_cards
      | again: %Card{
          scheduling_cards.again
          | scheduled_days: 0,
            due: DateTime.add(now, 5, :minute)
        },
        hard: %Card{
          scheduling_cards.hard
          | scheduled_days: hard_interval,
            due: hard_due
        },
        good: %Card{
          scheduling_cards.good
          | scheduled_days: good_interval,
            due: DateTime.add(now, good_interval, :day)
        },
        easy: %Card{
          scheduling_cards.easy
          | scheduled_days: easy_interval,
            due: DateTime.add(now, easy_interval, :day)
        }
    }
  end

  def record_log(scheduling_cards, card, now) do
    %{
      again: %SchedulingInfo{
        card: scheduling_cards.again,
        review_log: %ReviewLog{
          rating: :again,
          scheduled_days: scheduling_cards.again.scheduled_days,
          elapsed_days: card.elapsed_days,
          review: now,
          state: card.state
        }
      },
      hard: %SchedulingInfo{
        card: scheduling_cards.hard,
        review_log: %ReviewLog{
          rating: :hard,
          scheduled_days: scheduling_cards.hard.scheduled_days,
          elapsed_days: card.elapsed_days,
          review: now,
          state: card.state
        }
      },
      good: %SchedulingInfo{
        card: scheduling_cards.good,
        review_log: %ReviewLog{
          rating: :good,
          scheduled_days: scheduling_cards.good.scheduled_days,
          elapsed_days: card.elapsed_days,
          review: now,
          state: card.state
        }
      },
      easy: %SchedulingInfo{
        card: scheduling_cards.easy,
        review_log: %ReviewLog{
          rating: :easy,
          scheduled_days: scheduling_cards.easy.scheduled_days,
          elapsed_days: card.elapsed_days,
          review: now,
          state: card.state
        }
      }
    }
  end
end

defmodule FSRS do
  import SchedulingCards
  alias :math, as: Math

  defp mean_reversion(weights, init, current) do
    elem(weights, 7) * init + (1 - elem(weights, 7)) * current
  end

  defp init_stability(weights, r) do
    max(elem(weights, r - 1), 0.1)
  end

  defp init_difficulty(weights, r) do
    min(max(elem(weights, 4) - elem(weights, 5) * (r - 3), 1), 10)
  end

  defp next_interval(params, s) do
    new_interval = s * 9 * (1 / params.request_retention - 1)
    min(max(round(new_interval), 1), params.maximum_interval)
  end

  defp next_difficulty(weights, d, r) do
    next_d = d - elem(weights, 6) * (r - 3)
    min(max(mean_reversion(weights, elem(weights, 4), next_d), 1), 10)
  end

  defp next_recall_stability(weights, d, s, r, 2) do
    s *
      (1 +
         Math.exp(elem(weights, 8)) *
           (11 - d) *
           Math.pow(s, -elem(weights, 9)) *
           (Math.exp((1 - r) * elem(weights, 10)) - 1) *
           elem(weights, 15))
  end

  defp next_recall_stability(weights, d, s, r, 4) do
    s *
      (1 +
         Math.exp(elem(weights, 8)) *
           (11 - d) *
           Math.pow(s, -elem(weights, 9)) *
           (Math.exp((1 - r) * elem(weights, 10)) - 1) * elem(weights, 16))
  end

  defp next_recall_stability(weights, d, s, r, _rating) do
    s *
      (1 +
         Math.exp(elem(weights, 8)) *
           (11 - d) *
           Math.pow(s, -elem(weights, 9)) *
           (Math.exp((1 - r) * elem(weights, 10)) - 1))
  end

  defp next_forget_stability(weights, d, s, r) do
    elem(weights, 11) * Math.pow(d, -elem(weights, 12)) * (Math.pow(s + 1, elem(weights, 13)) - 1) *
      Math.exp((1 - r) * elem(weights, 14))
  end

  defp init_ds(s, weights) do
    rating = %{again: 1, hard: 2, good: 3, easy: 4}

    s = put_in(s.again.difficulty, init_difficulty(weights, rating.again))
    s = put_in(s.again.stability, init_stability(weights, rating.again))
    s = put_in(s.hard.difficulty, init_difficulty(weights, rating.hard))
    s = put_in(s.hard.stability, init_stability(weights, rating.hard))
    s = put_in(s.good.difficulty, init_difficulty(weights, rating.good))
    s = put_in(s.good.stability, init_stability(weights, rating.good))
    s = put_in(s.easy.difficulty, init_difficulty(weights, rating.easy))
    put_in(s.easy.stability, init_stability(weights, rating.easy))
  end

  defp next_ds(s, weights, last_d, last_s, retrievability) do
    rating = %{again: 1, hard: 2, good: 3, easy: 4}

    s = put_in(s.again.difficulty, next_difficulty(weights, last_d, rating.again))

    s =
      put_in(
        s.again.stability,
        next_forget_stability(weights, s.again.difficulty, last_s, retrievability)
      )

    s = put_in(s.hard.difficulty, next_difficulty(weights, last_d, rating.hard))

    s =
      put_in(
        s.hard.stability,
        next_recall_stability(
          weights,
          s.hard.difficulty,
          last_s,
          retrievability,
          rating.hard
        )
      )

    s = put_in(s.good.difficulty, next_difficulty(weights, last_d, rating.good))

    s =
      put_in(
        s.good.stability,
        next_recall_stability(
          weights,
          s.good.difficulty,
          last_s,
          retrievability,
          rating.good
        )
      )

    s = put_in(s.easy.difficulty, next_difficulty(weights, last_d, rating.easy))

    put_in(
      s.easy.stability,
      next_recall_stability(
        weights,
        s.easy.difficulty,
        last_s,
        retrievability,
        rating.easy
      )
    )
  end

  def repeat(params, %Card{state: :new} = card, now) do
    %Parameters{weights: weights} = params

    card = %Card{
      card
      | elapsed_days: 0,
        last_review: now,
        reps: card.reps + 1
    }

    s =
      %SchedulingCards{again: card, hard: card, good: card, easy: card}
      |> update_state(:new)
      |> init_ds(weights)

    easy_interval = next_interval(params, s.easy.stability)

    s = put_in(s.again.due, DateTime.add(now, 1, :minute))
    s = put_in(s.hard.due, DateTime.add(now, 5, :minute))
    s = put_in(s.good.due, DateTime.add(now, 10, :minute))
    s = put_in(s.easy.due, DateTime.add(now, easy_interval, :day))
    s = put_in(s.easy.scheduled_days, easy_interval)

    record_log(s, card, now)
  end

  def repeat(params, %Card{state: :review} = card, now) do
    %Parameters{weights: weights} = params

    card =
      %Card{stability: last_s, difficulty: last_d, elapsed_days: interval} =
      %Card{
        card
        | elapsed_days: DateTime.diff(now, card.last_review, :day),
          last_review: now,
          reps: card.reps + 1
      }

    retrievability = (1 + interval / (9 * last_s)) ** -1

    s =
      %SchedulingCards{again: card, hard: card, good: card, easy: card}
      |> update_state(:review)
      |> next_ds(weights, last_d, last_s, retrievability)

    hard_interval = next_interval(params, s.hard.stability)
    good_interval = next_interval(params, s.good.stability)
    hard_interval = min(hard_interval, good_interval)
    good_interval = max(good_interval, hard_interval + 1)
    easy_interval = max(next_interval(params, s.easy.stability), good_interval + 1)

    s = schedule(s, now, hard_interval, good_interval, easy_interval)
    record_log(s, card, now)
  end

  def repeat(params, card, now) do
    card = %Card{
      card
      | elapsed_days: DateTime.diff(now, card.last_review, :day),
        last_review: now,
        reps: card.reps + 1
    }

    s =
      %SchedulingCards{again: card, hard: card, good: card, easy: card}
      |> update_state(card.state)

    hard_interval = 0
    good_interval = next_interval(params, s.good.stability)
    easy_interval = max(next_interval(params, s.easy.stability), good_interval + 1)

    s = schedule(s, now, hard_interval, good_interval, easy_interval)
    record_log(s, card, now)
  end
end
