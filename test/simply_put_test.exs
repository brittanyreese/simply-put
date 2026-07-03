defmodule SimplyPutTest do
  use ExUnit.Case
  doctest SimplyPut

  test "greets the world" do
    assert SimplyPut.hello() == :world
  end
end
