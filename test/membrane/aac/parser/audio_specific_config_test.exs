defmodule Membrane.AAC.Parser.AudioSpecificConfigTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Membrane.AAC
  alias Membrane.AAC.Parser.AudioSpecificConfig

  describe "parse_audio_specific_config/1" do
    test "parses a valid config" do
      # AAC LC, 44 100 Hz, stereo, 1024 samples per frame
      assert {:ok, %AAC{profile: :LC, sample_rate: 44_100, channels: 2, samples_per_frame: 1024}} =
               AudioSpecificConfig.parse_audio_specific_config(<<2::5, 4::4, 2::4, 0::3>>)

      # explicit sample rate
      assert {:ok, %AAC{profile: :LC, sample_rate: 20_000, channels: 1}} =
               AudioSpecificConfig.parse_audio_specific_config(
                 <<2::5, 15::4, 20_000::24, 1::4, 0::3>>
               )
    end

    test "returns an error for a config that is too short" do
      assert {:error, :invalid_audio_specific_config} =
               AudioSpecificConfig.parse_audio_specific_config(<<>>)

      assert {:error, :invalid_audio_specific_config} =
               AudioSpecificConfig.parse_audio_specific_config(<<0x12>>)

      # explicit sample rate announced, but not present
      assert {:error, :invalid_audio_specific_config} =
               AudioSpecificConfig.parse_audio_specific_config(<<2::5, 15::4, 2::4, 0::3>>)
    end

    test "returns an error for reserved or unsupported field values" do
      # audio object type 23 (ER AAC LD)
      assert {:error, {:unsupported, :audio_object_type, 23}} =
               AudioSpecificConfig.parse_audio_specific_config(<<23::5, 4::4, 2::4, 0::3>>)

      # reserved sampling frequency id
      assert {:error, {:unsupported, :sampling_frequency, 13}} =
               AudioSpecificConfig.parse_audio_specific_config(<<2::5, 13::4, 2::4, 0::3>>)

      # reserved channel configuration
      assert {:error, {:unsupported, :channel_config, 9}} =
               AudioSpecificConfig.parse_audio_specific_config(<<2::5, 4::4, 9::4, 0::3>>)
    end
  end
end
