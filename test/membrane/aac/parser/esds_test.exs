defmodule Membrane.AAC.Parser.EsdsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Membrane.AAC
  alias Membrane.AAC.Parser.Esds

  describe "parse_esds/1" do
    test "tolerates a DecoderConfigDescriptor whose reserved bit is 0" do
      # Real esds captured from an MP4 whose encoder leaves the
      # DecoderConfigDescriptor "reserved" bit cleared: the second byte is
      # 0x14 (stream_type 5, upstream 0, reserved 0) instead of the
      # spec-mandated 0x15. ISO/IEC 14496-1 says the bit "should" be 1, but
      # many encoders emit 0 and a parser must not crash on otherwise-valid
      # streams.
      section_4 =
        <<64, 0x14, 0, 24, 0, 0, 1, 244, 0, 0, 1, 244, 0, 5, 128, 128, 128, 2, 0x11, 0x90>>

      section_4_wrapped = <<4, 128, 128, 128, byte_size(section_4), section_4::binary>>
      section_6 = <<6, 128, 128, 128, 1, 2>>
      section_3_payload = <<1::16, 0, section_4_wrapped::binary, section_6::binary>>
      esds = <<3, 128, 128, 128, byte_size(section_3_payload), section_3_payload::binary>>

      assert {:ok, %AAC{profile: :LC, sample_rate: 48_000, channels: 2}} = Esds.parse_esds(esds)
    end

    test "parses a DecoderConfigDescriptor whose reserved bit is the conformant 1" do
      section_4 =
        <<64, 0x15, 0, 24, 0, 0, 1, 244, 0, 0, 1, 244, 0, 5, 128, 128, 128, 2, 0x11, 0x90>>

      section_4_wrapped = <<4, 128, 128, 128, byte_size(section_4), section_4::binary>>
      section_6 = <<6, 128, 128, 128, 1, 2>>
      section_3_payload = <<1::16, 0, section_4_wrapped::binary, section_6::binary>>
      esds = <<3, 128, 128, 128, byte_size(section_3_payload), section_3_payload::binary>>

      assert {:ok, %AAC{profile: :LC, sample_rate: 48_000, channels: 2}} = Esds.parse_esds(esds)
    end

    test "returns an error for a malformed esds instead of raising" do
      section_4 =
        <<64, 0x15, 0, 24, 0, 0, 1, 244, 0, 0, 1, 244, 0, 5, 128, 128, 128, 2, 0x11, 0x90>>

      section_4_wrapped = <<4, 128, 128, 128, byte_size(section_4), section_4::binary>>
      section_6 = <<6, 128, 128, 128, 1, 2>>
      section_3_payload = <<1::16, 0, section_4_wrapped::binary, section_6::binary>>
      esds = <<3, 128, 128, 128, byte_size(section_3_payload), section_3_payload::binary>>

      # truncated
      for size <- 0..(byte_size(esds) - 1) do
        <<truncated::binary-size(size), _rest::binary>> = esds
        assert {:error, :invalid_esds} = Esds.parse_esds(truncated)
      end

      # wrong top-level tag
      assert {:error, :invalid_esds} = Esds.parse_esds(<<4, 128, 128, 128, 0>>)

      # DecoderConfigDescriptor of a non-audio stream (stream_type 4 = visual)
      <<prefix::binary-size(14), 0x15, rest::binary>> = esds
      assert {:error, :invalid_esds} = Esds.parse_esds(<<prefix::binary, 0x11, rest::binary>>)

      # AudioSpecificConfig with a reserved sampling frequency id (13)
      <<prefix::binary-size(31), 0x11, 0x90, suffix::binary>> = esds

      assert {:error, {:unsupported, :sampling_frequency, 13}} =
               Esds.parse_esds(<<prefix::binary, 0x16, 0x90, suffix::binary>>)
    end
  end
end
