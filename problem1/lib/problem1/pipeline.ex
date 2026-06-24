defmodule Problem1.Pipeline do

  def multiply(a, b) do
    matrix_size = length(a)

    unless is_square?(a, matrix_size) and is_square?(b, matrix_size) do
      raise ArgumentError, "Matrix need to be square (n x n)."
    end

    coordinator_pid = self()

    # workers em ordem reversa
    first_worker_pid =
      Enum.reduce((matrix_size - 1)..0//-1, coordinator_pid, fn worker_index, next_pid ->
        spawn_link(fn -> worker(worker_index, matrix_size, next_pid) end)
      end)

    # envia linhas de a
    Enum.each(a, fn row ->
      send(first_worker_pid, {:row_a, row})
    end)

    # envia colunas de b
    columns_b = transpose(b)
    Enum.each(columns_b, fn col ->
      send(first_worker_pid, {:col_b, col})
    end)

    # recebe linhas de c 
    c_rows =
      Enum.reduce((matrix_size - 1)..0//-1, %{}, fn i, acc ->
        receive do
          {:result, ^i, row_c} -> Map.put(acc, i, row_c)
        end
      end)

    # refaz c
    Enum.map(0..(matrix_size - 1), fn i -> Map.get(c_rows, i) end)
  end

  defp worker(worker_index, matrix_size, next_pid) do
    # pega linha
    my_row_a =
      receive do
        {:row_a, row} -> row
      end

    # repassa seguintes
    if worker_index < matrix_size - 1 do
      for _ <- (worker_index + 1)..(matrix_size - 1) do
        receive do
          {:row_a, row} -> send(next_pid, {:row_a, row})
        end
      end
    end

    # pega coluna e faz produto interno
    my_row_c =
      for _j <- 0..(matrix_size - 1) do
        col_b =
          receive do
            {:col_b, col} -> col
          end

        if worker_index < matrix_size - 1 do
          send(next_pid, {:col_b, col_b})
        end

        inner_product(my_row_a, col_b)
      end

    # envia linha de c pro próximo worker
    send(next_pid, {:result, worker_index, my_row_c})

    # recebe linhas de c do anterior
    if worker_index > 0 do
      for _i <- 0..(worker_index - 1) do
        receive do
          {:result, prev_w, prev_row_c} ->
            send(next_pid, {:result, prev_w, prev_row_c})
        end
      end
    end
  end

  defp inner_product(a, b) do
    Enum.zip(a, b) |> Enum.map(fn {x, y} -> x * y end) |> Enum.sum()
  end

  defp transpose(m) do
    m |> Enum.zip() |> Enum.map(&Tuple.to_list/1)
  end

  defp is_square?(matrix, matrix_size) do
    length(matrix) == matrix_size and Enum.all?(matrix, fn row -> length(row) == matrix_size end)
  end
end
