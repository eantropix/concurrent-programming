ExUnit.start()

Code.require_file("../../lib/problem1/pipeline.ex", __DIR__)

defmodule Problem1.PipelineTest do
  use ExUnit.Case

  alias Problem1.Pipeline

  test "multiplica 2x2" do
    a = [
      [1, 2],
      [3, 4]
    ]

    b = [
      [5, 6],
      [7, 8]
    ]

    # C = A * B
    # C[0,0] = 1*5 + 2*7 = 19
    # C[0,1] = 1*6 + 2*8 = 22
    # C[1,0] = 3*5 + 4*7 = 43
    # C[1,1] = 3*6 + 4*8 = 50
    c = [
      [19, 22],
      [43, 50]
    ]

    assert Pipeline.multiply(a, b) == c
  end

  test "multiplica 3x3" do
    a = [
      [1, 2, 3],
      [4, 5, 6],
      [7, 8, 9]
    ]

    b = [
      [9, 8, 7],
      [6, 5, 4],
      [3, 2, 1]
    ]

    # C[0,0] = 1*9 + 2*6 + 3*3 = 9 + 12 + 9 = 30
    # C[0,1] = 1*8 + 2*5 + 3*2 = 8 + 10 + 6 = 24
    # C[0,2] = 1*7 + 2*4 + 3*1 = 7 + 8 + 3 = 18
    # C[1,0] = 4*9 + 5*6 + 6*3 = 36 + 30 + 18 = 84
    # C[1,1] = 4*8 + 5*5 + 6*2 = 32 + 25 + 12 = 69
    # C[1,2] = 4*7 + 5*4 + 6*1 = 28 + 20 + 6 = 54
    # C[2,0] = 7*9 + 8*6 + 9*3 = 63 + 48 + 27 = 138
    # C[2,1] = 7*8 + 8*5 + 9*2 = 56 + 40 + 18 = 114
    # C[2,2] = 7*7 + 8*4 + 9*1 = 49 + 32 + 9 = 90

    c = [
      [30, 24, 18],
      [84, 69, 54],
      [138, 114, 90]
    ]

    assert Pipeline.multiply(a, b) == c
  end
end
