defmodule CamProjectTest do
  use ExUnit.Case
  doctest CamProject

  test "greets the world" do
    assert CamProject.hello() == :world
  end
end
