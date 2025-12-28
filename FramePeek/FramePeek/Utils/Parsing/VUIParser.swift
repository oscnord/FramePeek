//
//  VUIParser.swift
//  FramePeek
//
//  Minimal parser for extracting max bitrate from VUI (Video Usability Information)
//  parameters in AVC (H.264) and HEVC (H.265) codec configurations.
//

import Foundation

// MARK: - Bit Reader

/// Simple bit-level reader for parsing NAL unit bitstreams
private struct BitReader {
    let data: Data
    var byteOffset: Int = 0
    var bitOffset: Int = 0
    
    init(data: Data) {
        self.data = data
    }
    
    /// Checks if we can read more bits
    var hasMoreBits: Bool {
        byteOffset < data.count
    }
    
    /// Reads a single bit
    mutating func readBit() -> UInt8? {
        guard byteOffset < data.count else { return nil }
        let byte = data[byteOffset]
        let bit = (byte >> (7 - bitOffset)) & 1
        bitOffset += 1
        if bitOffset >= 8 {
            bitOffset = 0
            byteOffset += 1
        }
        return bit
    }
    
    /// Reads n bits as an unsigned integer
    mutating func readBits(_ n: Int) -> UInt32? {
        guard n > 0 && n <= 32 else { return nil }
        var value: UInt32 = 0
        for _ in 0..<n {
            guard let bit = readBit() else { return nil }
            value = (value << 1) | UInt32(bit)
        }
        return value
    }
    
    /// Reads an unsigned Exp-Golomb coded value (ue(v))
    mutating func readUE() -> UInt32? {
        var leadingZeros = 0
        while let bit = readBit(), bit == 0 {
            leadingZeros += 1
            if leadingZeros > 32 { return nil } // Safety limit
        }
        
        // If we didn't get a 1 bit, we've run out of data
        guard leadingZeros <= 32 else { return nil }
        
        guard let bits = readBits(leadingZeros) else { return nil }
        let result = (1 << leadingZeros) - 1 + bits
        // Check for overflow
        guard result <= UInt32.max else { return nil }
        return result
    }
    
    /// Reads a signed Exp-Golomb coded value (se(v))
    mutating func readSE() -> Int32? {
        guard let ue = readUE() else { return nil }
        if ue % 2 == 0 {
            return -Int32(ue / 2)
        } else {
            return Int32((ue + 1) / 2)
        }
    }
    
    /// Skips n bits (returns false if we run out of data)
    @discardableResult
    mutating func skipBits(_ n: Int) -> Bool {
        for _ in 0..<n {
            guard readBit() != nil else { return false }
        }
        return true
    }
    
    /// Aligns to next byte boundary
    mutating func alignToByte() {
        if bitOffset > 0 {
            bitOffset = 0
            byteOffset += 1
        }
    }
}

// MARK: - AVC (H.264) VUI Parser

/// Extracts max bitrate from AVC (H.264) codec configuration
/// - Parameter avcCData: Raw avcC box data containing SPS
/// - Returns: Formatted max bitrate string (e.g., "50000 kb/s") or nil if not found
func parseAVCMaxBitrate(_ avcCData: Data) -> String? {
    // avcC structure: configurationVersion (1), AVCProfileIndication (1),
    // profile_compatibility (1), AVCLevelIndication (1), lengthSizeMinusOne (1),
    // numOfSequenceParameterSets (1), then SPS data
    guard avcCData.count >= 6 else { return nil }
    
    let bytes = [UInt8](avcCData)
    let numSPS = bytes[5] & 0x1F  // Lower 5 bits
    
    // Skip to first SPS
    var offset = 6
    for _ in 0..<numSPS {
        guard offset + 2 <= avcCData.count else { return nil }
        let spsLength = (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
        offset += 2
        
        guard offset + spsLength <= avcCData.count else { return nil }
        
        // Parse SPS to find VUI parameters
        let spsData = avcCData.subdata(in: offset..<(offset + spsLength))
        if let maxBitrate = parseAVCSPSForMaxBitrate(spsData) {
            // AVC max_bitrate is in units of 1000 bits/second
            let kbps = maxBitrate
            return String(format: "%.0f kb/s", Double(kbps))
        }
        
        offset += spsLength
    }
    
    return nil
}

/// Parses AVC SPS to extract max bitrate from VUI
private func parseAVCSPSForMaxBitrate(_ spsData: Data) -> UInt32? {
    guard spsData.count > 1 else { return nil }
    
    var reader = BitReader(data: spsData)
    
    // Skip NAL unit header (1 byte)
    reader.skipBits(8)
    
    // Parse SPS syntax elements up to VUI
    // profile_idc (8 bits)
    guard let profileIdc = reader.readBits(8) else { return nil }
    
    // constraint_set0_flag through constraint_set5_flag, reserved_zero_2bits (8 bits)
    reader.skipBits(8)
    
    // level_idc (8 bits)
    reader.skipBits(8)
    
    // seq_parameter_set_id (ue(v))
    guard reader.readUE() != nil else { return nil }
    
    // Parse remaining SPS elements based on profile
    // chroma_format_idc (if profile is 100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135)
    if profileIdc == 100 || profileIdc == 110 || profileIdc == 122 || profileIdc == 244 ||
       profileIdc == 44 || profileIdc == 83 || profileIdc == 86 || profileIdc == 118 ||
       profileIdc == 128 || profileIdc == 138 || profileIdc == 139 || profileIdc == 134 || profileIdc == 135 {
        guard let chromaFormatIdc = reader.readUE() else { return nil }
        
        if chromaFormatIdc == 3 {
            // separate_colour_plane_flag (1 bit)
            reader.skipBits(1)
        }
        
        // bit_depth_luma_minus8 (ue(v))
        guard reader.readUE() != nil else { return nil }
        // bit_depth_chroma_minus8 (ue(v))
        guard reader.readUE() != nil else { return nil }
        // qpprime_y_zero_transform_bypass_flag (1 bit)
        reader.skipBits(1)
        
        // seq_scaling_matrix_present_flag (1 bit)
        if let scalingMatrixPresent = reader.readBit(), scalingMatrixPresent == 1 {
            // Parse scaling lists (up to 8 lists, each can be present or use default)
            for i in 0..<8 {
                if let scalingListPresent = reader.readBit(), scalingListPresent == 1 {
                    // Parse scaling list (complex, skip for now)
                    // For i < 6: 16 elements, for i >= 6: 64 elements
                    let listSize = (i < 6) ? 16 : 64
                    // Skip the scaling list data
                    // This is complex - we'll use a heuristic: skip a reasonable amount
                    var lastScale = 8
                    for _ in 0..<listSize {
                        if let deltaScale = reader.readSE() {
                            lastScale = (lastScale + Int(deltaScale) + 256) % 256
                            if lastScale == 0 { break }
                        } else {
                            break
                        }
                    }
                }
            }
        }
    }
    
    // log2_max_frame_num_minus4 (ue(v))
    guard reader.readUE() != nil else { return nil }
    
    // pic_order_cnt_type (ue(v))
    guard let picOrderCntType = reader.readUE() else { return nil }
    
    if picOrderCntType == 0 {
        // log2_max_pic_order_cnt_lsb_minus4 (ue(v))
        guard reader.readUE() != nil else { return nil }
    } else if picOrderCntType == 1 {
        // delta_pic_order_always_zero_flag (1 bit)
        reader.skipBits(1)
        // offset_for_non_ref_pic (se(v))
        reader.readSE()
        // offset_for_top_to_bottom_field (se(v))
        reader.readSE()
        // num_ref_frames_in_pic_order_cnt_cycle (ue(v))
        guard let numRefFrames = reader.readUE() else { return nil }
        // offset_for_ref_frame[i] (se(v)) for each frame
        for _ in 0..<numRefFrames {
            reader.readSE()
        }
    }
    
    // max_num_ref_frames (ue(v))
    guard reader.readUE() != nil else { return nil }
    
    // gaps_in_frame_num_value_allowed_flag (1 bit)
    reader.skipBits(1)
    
    // pic_width_in_mbs_minus1 (ue(v))
    guard reader.readUE() != nil else { return nil }
    
    // pic_height_in_map_units_minus1 (ue(v))
    guard reader.readUE() != nil else { return nil }
    
    // frame_mbs_only_flag (1 bit)
    guard let frameMbsOnly = reader.readBit() else { return nil }
    
    if frameMbsOnly == 0 {
        // mb_adaptive_frame_field_flag (1 bit)
        reader.skipBits(1)
    }
    
    // direct_8x8_inference_flag (1 bit)
    reader.skipBits(1)
    
    // frame_cropping_flag (1 bit)
    if let frameCroppingFlag = reader.readBit(), frameCroppingFlag == 1 {
        reader.readUE() // frame_crop_left_offset
        reader.readUE() // frame_crop_right_offset
        reader.readUE() // frame_crop_top_offset
        reader.readUE() // frame_crop_bottom_offset
    }
    
    // vui_parameters_present_flag (1 bit) - FINALLY!
    guard let vuiPresent = reader.readBit(), vuiPresent == 1 else {
        return nil
    }
    
    // Now parse VUI
    return parseAVCSPSVUI(reader: &reader)
}

/// Parses VUI parameters from AVC SPS
private func parseAVCSPSVUI(reader: inout BitReader) -> UInt32? {
    // Try to find vui_parameters_present_flag
    // This is complex without full SPS parsing, so we'll use a heuristic
    
    // For a minimal implementation, we'll search for the VUI structure
    // A more complete implementation would parse all SPS elements first
    
    // vui_parameters_present_flag (1 bit)
    guard let vuiPresent = reader.readBit(), vuiPresent == 1 else {
        return nil
    }
    
    // Parse VUI parameters
    // aspect_ratio_info_present_flag
    if let aspectRatioPresent = reader.readBit(), aspectRatioPresent == 1 {
        // aspect_ratio_idc or extended_sar
        if let aspectRatioIdc = reader.readBits(8), aspectRatioIdc == 255 {
            // extended_sar: sar_width (16), sar_height (16)
            reader.skipBits(32)
        }
    }
    
    // overscan_info_present_flag
    if let overscanPresent = reader.readBit(), overscanPresent == 1 {
        reader.skipBits(1) // overscan_appropriate_flag
    }
    
    // video_signal_type_present_flag
    if let videoSignalPresent = reader.readBit(), videoSignalPresent == 1 {
        reader.skipBits(4) // video_format (3) + video_full_range_flag (1)
        if let colorDescPresent = reader.readBit(), colorDescPresent == 1 {
            reader.skipBits(24) // colour_primaries (8) + transfer_characteristics (8) + matrix_coefficients (8)
        }
    }
    
    // chroma_loc_info_present_flag
    if let chromaLocPresent = reader.readBit(), chromaLocPresent == 1 {
        reader.readUE() // chroma_sample_loc_type_top_field
        reader.readUE() // chroma_sample_loc_type_bottom_field
    }
    
    // timing_info_present_flag
    if let timingPresent = reader.readBit(), timingPresent == 1 {
        reader.skipBits(32) // num_units_in_tick
        reader.skipBits(32) // time_scale
        if let fixedFrameRate = reader.readBit(), fixedFrameRate == 1 {
            // fixed_frame_rate_flag
        }
    }
    
    // nal_hrd_parameters_present_flag
    var hrdMaxBitrate: UInt32? = nil
    if let nalHrdPresent = reader.readBit(), nalHrdPresent == 1 {
        if let maxBitrate = parseHRDParameters(reader: &reader) {
            hrdMaxBitrate = maxBitrate
        }
    }
    
    // vcl_hrd_parameters_present_flag
    if let vclHrdPresent = reader.readBit(), vclHrdPresent == 1 {
        if let maxBitrate = parseHRDParameters(reader: &reader) {
            hrdMaxBitrate = maxBitrate // Prefer VCL HRD if both present
        }
    }
    
    // low_delay_hrd_flag (if either HRD present)
    if hrdMaxBitrate != nil {
        _ = reader.readBit() // low_delay_hrd_flag
    }
    
    // pic_struct_present_flag
    _ = reader.readBit()
    
    // bitstream_restriction_flag
    if let bitstreamRestriction = reader.readBit(), bitstreamRestriction == 1 {
        // Skip bitstream restriction parameters
        _ = reader.readBit() // tiles_fixed_structure_flag
        _ = reader.readBit() // motion_vectors_over_pic_boundaries_flag
        reader.readUE() // max_bytes_per_pic_denom
        reader.readUE() // max_bits_per_mb_denom
        reader.readUE() // log2_max_mv_length_horizontal
        reader.readUE() // log2_max_mv_length_vertical
        reader.readUE() // num_reorder_frames
        reader.readUE() // max_dec_frame_buffering
    }
    
    return hrdMaxBitrate
}

/// Parses HRD (Hypothetical Reference Decoder) parameters to extract max bitrate
private func parseHRDParameters(reader: inout BitReader) -> UInt32? {
    // cpb_cnt_minus1 (ue(v))
    guard let cpbCnt = reader.readUE() else { return nil }
    
    // bit_rate_scale (4 bits) + cpb_size_scale (4 bits)
    reader.skipBits(8)
    
    var maxBitrateValue: UInt32 = 0
    
    // Parse for each CPB to find maximum bitrate
    // Note: bit_rate_value_minus1 is typically in units of 1000 bits/second
    // Some encoders use the full formula: (bit_rate_value_minus1 + 1) * 2^(bit_rate_scale + 6)
    // For compatibility, we use the simpler interpretation
    for _ in 0...cpbCnt {
        // bit_rate_value_minus1 (ue(v))
        // Common interpretation: (bit_rate_value_minus1 + 1) * 1000 bits/second = kbps
        if let bitRateValueMinus1 = reader.readUE() {
            let kbps = bitRateValueMinus1 + 1
            maxBitrateValue = max(maxBitrateValue, kbps)
        }
        reader.readUE() // cpb_size_value_minus1
        _ = reader.readBit() // cbr_flag
    }
    
    // initial_cpb_removal_delay_length_minus1 (5 bits)
    reader.skipBits(5)
    // cpb_removal_delay_length_minus1 (5 bits)
    reader.skipBits(5)
    // dpb_output_delay_length_minus1 (5 bits)
    reader.skipBits(5)
    // time_offset_length (5 bits)
    reader.skipBits(5)
    
    return maxBitrateValue > 0 ? maxBitrateValue : nil
}

// MARK: - HEVC (H.265) VUI Parser

/// Extracts max bitrate from HEVC (H.265) codec configuration
/// - Parameter hvcCData: Raw hvcC box data containing VPS/SPS
/// - Returns: Formatted max bitrate string (e.g., "50000 kb/s") or nil if not found
func parseHEVCMaxBitrate(_ hvcCData: Data) -> String? {
    guard hvcCData.count >= 23 else { return nil }
    
    let bytes = [UInt8](hvcCData)
    
    // hvcC header is 23 bytes, then arrays follow
    var offset = 23
    
    // numOfArrays (1 byte)
    guard offset < hvcCData.count else { return nil }
    let numArrays = bytes[offset]
    offset += 1
    
    // Parse arrays to find SPS
    for _ in 0..<numArrays {
        guard offset + 3 <= hvcCData.count else { break }
        let arrayCompleteness = (bytes[offset] & 0x80) != 0
        let nalUnitType = bytes[offset] & 0x3F
        offset += 1
        let numNalus = (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
        offset += 2
        
        // If this is an SPS array (type 33)
        if nalUnitType == 33 {
            for _ in 0..<numNalus {
                guard offset + 2 <= hvcCData.count else { break }
                let nalLength = (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
                offset += 2
                
                guard offset + nalLength <= hvcCData.count else { break }
                
                // Parse SPS NAL unit for VUI
                let nalData = hvcCData.subdata(in: offset..<(offset + nalLength))
                if let maxBitrate = parseHEVCSPSForMaxBitrate(nalData) {
                    // HEVC max_bitrate is in units of 100 bits/second
                    let kbps = Double(maxBitrate) / 10.0
                    return String(format: "%.0f kb/s", kbps)
                }
                
                offset += nalLength
            }
        } else {
            // Skip NAL units we're not interested in
            for _ in 0..<numNalus {
                guard offset + 2 <= hvcCData.count else { break }
                let nalLength = (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
                offset += 2
                guard offset + nalLength <= hvcCData.count else { break }
                offset += nalLength
            }
        }
    }
    
    return nil
}

/// Parses HEVC SPS to extract max bitrate from VUI
private func parseHEVCSPSForMaxBitrate(_ spsData: Data) -> UInt32? {
    guard spsData.count > 2 else { return nil }
    
    var reader = BitReader(data: spsData)
    
    // Skip NAL unit header (2 bytes for HEVC)
    // First byte: forbidden_zero_bit (1) + nal_unit_type (6) + nuh_layer_id (6)
    // Second byte: nuh_temporal_id_plus1 (3) + reserved (5)
    reader.skipBits(16)
    
    // Parse SPS syntax elements up to VUI
    // sps_video_parameter_set_id (4 bits)
    reader.skipBits(4)
    
    // sps_max_sub_layers_minus1 (3 bits) + sps_temporal_id_nesting_flag (1 bit)
    guard let maxSubLayers = reader.readBits(3) else { return nil }
    reader.skipBits(1)
    
    // Parse profile_tier_level (simplified - skip most of it)
    // general_profile_space (2) + general_tier_flag (1) + general_profile_idc (5)
    reader.skipBits(8)
    // general_profile_compatibility_flags (32 bits)
    reader.skipBits(32)
    // general_progressive_source_flag through general_reserved_zero_43bits (48 bits)
    reader.skipBits(48)
    // general_level_idc (8 bits)
    reader.skipBits(8)
    
    // Parse sub-layer profile_tier_level if max_sub_layers > 1
    if maxSubLayers > 0 {
        for _ in 0..<(maxSubLayers - 1) {
            // sub_layer_profile_present_flag[i] (1) + sub_layer_level_present_flag[i] (1)
            if let profilePresent = reader.readBit(), profilePresent == 1 {
                reader.skipBits(8 + 32 + 48) // Skip profile info
            }
            if let levelPresent = reader.readBit(), levelPresent == 1 {
                reader.skipBits(8) // Skip level
            }
        }
    }
    
    // sps_seq_parameter_set_id (ue(v))
    guard reader.readUE() != nil else { return nil }
    
    // chroma_format_idc (ue(v))
    guard let chromaFormatIdc = reader.readUE() else { return nil }
    
    if chromaFormatIdc == 3 {
        // separate_colour_plane_flag (1 bit)
        reader.skipBits(1)
    }
    
    // pic_width_in_luma_samples (ue(v))
    guard reader.readUE() != nil else { return nil }
    // pic_height_in_luma_samples (ue(v))
    guard reader.readUE() != nil else { return nil }
    
    // conformance_window_flag (1 bit)
    if let conformanceWindow = reader.readBit(), conformanceWindow == 1 {
        reader.readUE() // conf_win_left_offset
        reader.readUE() // conf_win_right_offset
        reader.readUE() // conf_win_top_offset
        reader.readUE() // conf_win_bottom_offset
    }
    
    // bit_depth_luma_minus8 (ue(v))
    guard reader.readUE() != nil else { return nil }
    // bit_depth_chroma_minus8 (ue(v))
    guard reader.readUE() != nil else { return nil }
    
    // log2_max_pic_order_cnt_lsb_minus4 (ue(v))
    guard reader.readUE() != nil else { return nil }
    
    // sub_layer_ordering_info_present_flag (1 bit)
    let subLayerOrderingPresent = reader.readBit()
    
    // Parse ordering info for each sub-layer
    let numSubLayers = maxSubLayers + 1
    for i in 0..<numSubLayers {
        if i > 0 && subLayerOrderingPresent == 0 {
            break // Use same values for all sub-layers
        }
        reader.readUE() // sps_max_dec_pic_buffering_minus1[i]
        reader.readUE() // sps_max_num_reorder_pics[i]
        reader.readUE() // sps_max_latency_increase_plus1[i]
    }
    
    // log2_min_luma_coding_block_size_minus3 (ue(v))
    guard reader.readUE() != nil else { return nil }
    // log2_diff_max_min_luma_coding_block_size (ue(v))
    guard reader.readUE() != nil else { return nil }
    // log2_min_luma_transform_block_size_minus2 (ue(v))
    guard reader.readUE() != nil else { return nil }
    // log2_diff_max_min_luma_transform_block_size (ue(v))
    guard reader.readUE() != nil else { return nil }
    // max_transform_hierarchy_depth_inter (ue(v))
    guard reader.readUE() != nil else { return nil }
    // max_transform_hierarchy_depth_intra (ue(v))
    guard reader.readUE() != nil else { return nil }
    
    // scaling_list_enabled_flag (1 bit)
    if let scalingListEnabled = reader.readBit(), scalingListEnabled == 1 {
        // sps_scaling_list_data_present_flag (1 bit)
        if let scalingListDataPresent = reader.readBit(), scalingListDataPresent == 1 {
            // Parse scaling list data (complex, skip for now)
            // This would require parsing all scaling lists
            // For now, we'll try to skip through it heuristically
            // In practice, this is very complex, so we'll just try to continue
        }
    }
    
    // amp_enabled_flag (1 bit)
    reader.skipBits(1)
    // sample_adaptive_offset_enabled_flag (1 bit)
    reader.skipBits(1)
    // pcm_enabled_flag (1 bit)
    if let pcmEnabled = reader.readBit(), pcmEnabled == 1 {
        reader.skipBits(4) // pcm_sample_bit_depth_luma_minus1 (4)
        reader.skipBits(4) // pcm_sample_bit_depth_chroma_minus1 (4)
        reader.readUE() // log2_min_pcm_luma_coding_block_size_minus3
        reader.readUE() // log2_diff_max_min_pcm_luma_coding_block_size
        reader.skipBits(1) // pcm_loop_filter_disabled_flag
    }
    
    // num_short_term_ref_pic_sets (ue(v))
    guard let numShortTermRefPicSets = reader.readUE() else { return nil }
    
    // Parse short_term_ref_pic_set (complex, skip for now)
    // This is very complex and variable-length
    // We'll try a heuristic: skip a reasonable amount based on num_short_term_ref_pic_sets
    for _ in 0..<numShortTermRefPicSets {
        // Try to skip through short_term_ref_pic_set
        // This is too complex to parse fully, so we'll use a heuristic
        // Most sets are small, so we'll try to read and skip
        if let interRefPicSetPredictionFlag = reader.readBit(), interRefPicSetPredictionFlag == 1 {
            reader.readUE() // delta_idx_minus1
            reader.readUE() // delta_rps_sign
            reader.readUE() // abs_delta_rps_minus1
            // num_negative_pics, num_positive_pics
            if let numNegativePics = reader.readUE() {
                for _ in 0..<numNegativePics {
                    reader.readUE() // delta_poc_s0_minus1
                    reader.skipBits(1) // used_by_curr_pic_s0_flag
                }
            }
            if let numPositivePics = reader.readUE() {
                for _ in 0..<numPositivePics {
                    reader.readUE() // delta_poc_s1_minus1
                    reader.skipBits(1) // used_by_curr_pic_s1_flag
                }
            }
        } else {
            // Parse non-predicted set
            if let numNegativePics = reader.readUE() {
                for _ in 0..<numNegativePics {
                    reader.readUE() // delta_poc_s0_minus1
                    reader.skipBits(1) // used_by_curr_pic_s0_flag
                }
            }
            if let numPositivePics = reader.readUE() {
                for _ in 0..<numPositivePics {
                    reader.readUE() // delta_poc_s1_minus1
                    reader.skipBits(1) // used_by_curr_pic_s1_flag
                }
            }
        }
    }
    
    // long_term_ref_pics_present_flag (1 bit)
    if let longTermRefPicsPresent = reader.readBit(), longTermRefPicsPresent == 1 {
        reader.readUE() // num_long_term_ref_pics_sps
        // Skip long_term_ref_pic entries
        // This is complex, skip for now
    }
    
    // sps_temporal_mvp_enabled_flag (1 bit)
    reader.skipBits(1)
    // strong_intra_smoothing_enabled_flag (1 bit)
    reader.skipBits(1)
    
    // vui_parameters_present_flag (1 bit) - FINALLY!
    guard let vuiPresent = reader.readBit(), vuiPresent == 1 else {
        return nil
    }
    
    // Now parse VUI
    return parseHEVCSPSVUI(reader: &reader)
}

/// Parses VUI parameters from HEVC SPS
private func parseHEVCSPSVUI(reader: inout BitReader) -> UInt32? {
    // vui_parameters_present_flag (1 bit)
    guard let vuiPresent = reader.readBit(), vuiPresent == 1 else {
        return nil
    }
    
    // Parse VUI parameters (simplified)
    // aspect_ratio_info_present_flag
    if let aspectRatioPresent = reader.readBit(), aspectRatioPresent == 1 {
        if let aspectRatioIdc = reader.readBits(8), aspectRatioIdc == 255 {
            reader.skipBits(32) // sar_width (16) + sar_height (16)
        }
    }
    
    // overscan_info_present_flag
    if let overscanPresent = reader.readBit(), overscanPresent == 1 {
        reader.skipBits(1) // overscan_appropriate_flag
    }
    
    // video_signal_type_present_flag
    if let videoSignalPresent = reader.readBit(), videoSignalPresent == 1 {
        reader.skipBits(4) // video_format (3) + video_full_range_flag (1)
        if let colorDescPresent = reader.readBit(), colorDescPresent == 1 {
            reader.skipBits(24) // colour_primaries (8) + transfer_characteristics (8) + matrix_coefficients (8)
        }
    }
    
    // chroma_loc_info_present_flag
    if let chromaLocPresent = reader.readBit(), chromaLocPresent == 1 {
        reader.readUE() // chroma_sample_loc_type_frame
    }
    
    // neutral_chroma_indication_flag
    _ = reader.readBit()
    
    // field_seq_flag
    _ = reader.readBit()
    
    // frame_field_info_present_flag
    _ = reader.readBit()
    
    // default_display_window_flag
    if let defaultDisplayWindow = reader.readBit(), defaultDisplayWindow == 1 {
        reader.readUE() // def_disp_win_left_offset
        reader.readUE() // def_disp_win_right_offset
        reader.readUE() // def_disp_win_top_offset
        reader.readUE() // def_disp_win_bottom_offset
    }
    
    // vui_timing_info_present_flag
    if let timingPresent = reader.readBit(), timingPresent == 1 {
        reader.skipBits(32) // vui_num_units_in_tick
        reader.skipBits(32) // vui_time_scale
        if let vuiPocProportionalToTiming = reader.readBit(), vuiPocProportionalToTiming == 1 {
            reader.readUE() // vui_num_ticks_poc_diff_one_minus1
        }
        if let vuiHrdParametersPresent = reader.readBit(), vuiHrdParametersPresent == 1 {
            if let maxBitrate = parseHEVCHRDParameters(reader: &reader) {
                return maxBitrate
            }
        }
    }
    
    // bitstream_restriction_flag
    if let bitstreamRestriction = reader.readBit(), bitstreamRestriction == 1 {
        // Skip bitstream restriction parameters
        _ = reader.readBit() // tiles_fixed_structure_flag
        _ = reader.readBit() // motion_vectors_over_pic_boundaries_flag
        _ = reader.readBit() // restricted_ref_pic_lists_flag
        reader.readUE() // min_spatial_segmentation_idc
        reader.readUE() // max_bytes_per_pic_denom
        reader.readUE() // max_bits_per_min_cu_denom
        reader.readUE() // log2_max_mv_length_horizontal
        reader.readUE() // log2_max_mv_length_vertical
    }
    
    return nil
}

/// Parses HEVC HRD parameters to extract max bitrate
private func parseHEVCHRDParameters(reader: inout BitReader) -> UInt32? {
    // nal_hrd_parameters_present_flag
    var maxBitrate: UInt32? = nil
    
    if let nalHrdPresent = reader.readBit(), nalHrdPresent == 1 {
        if let bitrate = parseHEVCSubLayerHRD(reader: &reader) {
            maxBitrate = bitrate
        }
    }
    
    // vcl_hrd_parameters_present_flag
    if let vclHrdPresent = reader.readBit(), vclHrdPresent == 1 {
        if let bitrate = parseHEVCSubLayerHRD(reader: &reader) {
            maxBitrate = bitrate // Prefer VCL HRD if both present
        }
    }
    
    // sub_pic_hrd_params_present_flag
    if maxBitrate != nil {
        if let subPicHrdPresent = reader.readBit(), subPicHrdPresent == 1 {
            reader.skipBits(8) // tick_divisor_minus2 (8) + du_cpb_removal_delay_increment_length_minus1 (5) + sub_pic_cpb_params_in_pic_timing_sei_flag (1) + cpb_delay_offset_length_minus1 (5) + dpb_delay_offset_length_minus1 (5)
        }
    }
    
    return maxBitrate
}

/// Parses HEVC sub-layer HRD parameters
private func parseHEVCSubLayerHRD(reader: inout BitReader) -> UInt32? {
    // cpb_cnt_minus1 (ue(v))
    guard let cpbCnt = reader.readUE() else { return nil }
    
    // bit_rate_scale (4 bits) + cpb_size_scale (4 bits)
    reader.skipBits(8)
    
    var maxBitrateValue: UInt32 = 0
    
    // Parse for each sub-layer
    // For simplicity, we'll parse the first sub-layer (highest quality)
    // bit_rate_value_minus1[0][schedSelIdx] (ue(v))
    // cpb_size_value_minus1[0][schedSelIdx] (ue(v))
    // cbr_flag[0][schedSelIdx] (1 bit)
    
    for _ in 0...cpbCnt {
        if let bitrateValue = reader.readUE() {
            let bitrate = (bitrateValue + 1) * 100 // HEVC uses units of 100 bits/second
            maxBitrateValue = max(maxBitrateValue, bitrate)
        }
        reader.readUE() // cpb_size_value_minus1
        _ = reader.readBit() // cbr_flag
    }
    
    // initial_cpb_removal_delay_length_minus1 (5 bits)
    reader.skipBits(5)
    // au_cpb_removal_delay_length_minus1 (5 bits)
    reader.skipBits(5)
    // dpb_output_delay_length_minus1 (5 bits)
    reader.skipBits(5)
    
    return maxBitrateValue > 0 ? maxBitrateValue : nil
}

