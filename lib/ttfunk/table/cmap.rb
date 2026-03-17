# frozen_string_literal: true

module TTFunk
  class Table
    # Character to Glyph Index Mapping (`cmap`) table.
    class Cmap < Table
      # Table version.
      # @return [Integer]
      attr_reader :version

      # Encoding tables.
      # @return [Array<TTFunk::Table::Cmap::Subtable>]
      attr_reader :tables

      # Encode table.
      #
      # @param charmap [Hash{Integer => Integer}]
      # @param encoding [Symbol]
      # @return [Hash]
      #   * `:charmap` (<tt>Hash{Integer => Hash}</tt>) keys are the characrers in
      #     `charset`, values are hashes:
      #     * `:old` (<tt>Integer</tt>) - glyph ID in the original font.
      #     * `:new` (<tt>Integer</tt>) - glyph ID in the subset font.
      #     that maps the characters in charmap to a
      #   * `:table` (<tt>String</tt>) - serialized table.
      #   * `:max_glyph_id` (<tt>Integer</tt>) - maximum glyph ID in the new font.
      def self.encode(charmap, encoding)
        # Always encode the requested encoding (unicode = platform 3, encoding 1)
        unicode_result = Cmap::Subtable.encode(charmap, encoding)

        # Also encode Mac Roman (platform 1, encoding 0) so that Illustrator
        # can correctly resolve glyph IDs when editing embedded font text.
        # Without this subtable, Illustrator falls back to treating glyph IDs
        # as raw character codes, producing gobbledygook.
        #
        # Only characters in the Mac Roman range (0x00-0xFF) can be included.
        mac_charmap = charmap.select { |code, _| code <= 0xFF }
        mac_result = Cmap::Subtable.encode(mac_charmap, :mac_roman)

        # cmap header: version=0, table-count=2
        # Each subtable record is: platform_id(2) + encoding_id(2) + offset(4) = 8 bytes
        # Header = version(2) + count(2) = 4 bytes
        # Two subtable records = 2 * 8 = 16 bytes
        # Total header block = 4 + 16 = 20 bytes
        #
        # Subtables are appended after the header block.
        # Offset for first subtable (mac) starts right after header block.
        # Offset for second subtable (unicode) starts after mac subtable data.
        header_size = 4  # version + numTables
        record_size = 8  # platformID + encodingID + offset (each record)
        num_tables   = 2

        # Extract raw subtable bytes (without the platform/encoding/offset header record)
        # subtable field in result already contains: [platform_id, encoding_id, offset, data]
        # but we packed it as 'nnNA*' — we need just the raw cmap format data
        # Re-encode subtables as raw format data only (strip the 8-byte record header)
        mac_raw     = mac_result[:subtable][8..]     # skip platform(2)+encoding(2)+offset(4)
        unicode_raw = unicode_result[:subtable][8..]

        base_offset = header_size + (num_tables * record_size)
        mac_offset     = base_offset
        unicode_offset = base_offset + mac_raw.bytesize

        table = [0, num_tables].pack('nn')
        # Mac Roman record
        table += [1, 0, mac_offset].pack('nnN')
        # Windows Unicode record
        table += [3, 1, unicode_offset].pack('nnN')
        # Subtable data
        table += mac_raw
        table += unicode_raw

        unicode_result.merge(table: table)
      end

      # Get Unicode encoding records.
      #
      # @return [Array<TTFunk::Table::Cmap::Subtable>]
      def unicode
        # Because most callers just call .first on the result, put tables with
        # highest-number format first. Unsupported formats will be ignored.
        @unicode ||=
          @tables
            .select { |table| table.unicode? && table.supported? }
            .sort { |a, b| b.format <=> a.format }
      end

      private

      def parse!
        @version, table_count = read(4, 'nn')
        @tables =
          Array.new(table_count) do
            Cmap::Subtable.new(file, offset)
          end
      end
    end
  end
end

require_relative 'cmap/subtable'
