defmodule FSRSTest do
  use ExUnit.Case

  def generate_test_cards() do
    weights =
      {1.14, 1.01, 5.44, 14.67, 5.3024, 1.5662, 1.2503, 0.0028, 1.5489, 0.1763, 0.9953, 2.7473,
       0.0179, 0.3105, 0.3976, 0.0, 2.0902}

    params = %Parameters{weights: weights}
    card = %Card{}
    {:ok, now, 0} = DateTime.from_iso8601("2022-11-29T12:30:00Z")
    {params, FSRS.repeat(params, card, now), now}
  end

  test "scheduling" do
    ratings = [
      :good,
      :good,
      :good,
      :good,
      :good,
      :good,
      :again,
      :again,
      :good,
      :good,
      :good,
      :good,
      :good
    ]

    {p, s, _n} = generate_test_cards()

    {s, i} =
      Enum.reduce(ratings, {s, []}, fn rating, {s, i} ->
        card = Map.get(s, rating).card
        i = [card.scheduled_days] ++ i
        s = FSRS.repeat(p, card, card.due)
        {s, i}
      end)

    assert Enum.reverse(i) == [0, 5, 16, 43, 106, 236, 0, 0, 12, 25, 47, 85, 147]
    assert Card.get_retrievability(s.good.card, s.good.card.due) == 0.9000082565263599
  end

  test "first review" do
    {_p, s, _n} = generate_test_cards()

    assert s.again.card == %Card{
             due: ~U[2022-11-29 12:31:00Z],
             stability: 1.14,
             difficulty: 8.4348,
             elapsed_days: 0,
             scheduled_days: 0,
             reps: 1,
             lapses: 1,
             state: :learning,
             last_review: ~U[2022-11-29 12:30:00Z]
           }

    assert s.hard.card == %Card{
             due: ~U[2022-11-29 12:35:00Z],
             stability: 1.01,
             difficulty: 6.8686,
             elapsed_days: 0,
             scheduled_days: 0,
             reps: 1,
             lapses: 0,
             state: :learning,
             last_review: ~U[2022-11-29 12:30:00Z]
           }

    assert s.good.card == %Card{
             due: ~U[2022-11-29 12:40:00Z],
             stability: 5.44,
             difficulty: 5.3024,
             elapsed_days: 0,
             scheduled_days: 0,
             reps: 1,
             lapses: 0,
             state: :learning,
             last_review: ~U[2022-11-29 12:30:00Z]
           }

    assert s.easy.card == %Card{
             due: ~U[2022-12-14 12:30:00Z],
             stability: 14.67,
             difficulty: 3.7361999999999993,
             elapsed_days: 0,
             scheduled_days: 15,
             reps: 1,
             lapses: 0,
             state: :review,
             last_review: ~U[2022-11-29 12:30:00Z]
           }
  end

  test "elapsed_days" do
    {p, s, _} = generate_test_cards()
    c = s.good.card
    {:ok, n, 0} = DateTime.from_iso8601("2023-06-01T12:30:00Z")
    s2 = FSRS.repeat(p, c, n)
    c2 = s2.good.card
    {:ok, n2, 0} = DateTime.from_iso8601("2023-12-01T12:30:00Z")
    s3 = FSRS.repeat(p, c2, n2)

    assert s3.good.card.stability == 134.5276128635202
    assert Card.get_retrievability(s3.good.card, s3.good.card.due) == 0.8996840803331014
  end
end
