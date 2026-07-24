# Changelog

## [1.2.0](https://github.com/oscnord/FramePeek/compare/v1.1.0...v1.2.0) (2026-07-24)


### Features

* two-channel updates - Sparkle for GitHub, App Store target split ([#42](https://github.com/oscnord/FramePeek/issues/42)) ([9f38101](https://github.com/oscnord/FramePeek/commit/9f381019596ecc8ecfa9ac9aa2e1dd5fa2135074))

## [1.1.0](https://github.com/oscnord/FramePeek/compare/v1.0.0...v1.1.0) (2026-07-24)


### Features

* report real per-phase job progress over the REST API ([#35](https://github.com/oscnord/FramePeek/issues/35)) ([22767fd](https://github.com/oscnord/FramePeek/commit/22767fdd2fd107a2e4b7d570ef34412c893f0892))


### Bug Fixes

* correct Planckian locus math behind CCT confidence, color analysis perf ([#24](https://github.com/oscnord/FramePeek/issues/24)) ([15fe619](https://github.com/oscnord/FramePeek/commit/15fe619e4e12561ee4b12f1feacda89478747e91))
* harden media parsers against malformed files ([#20](https://github.com/oscnord/FramePeek/issues/20)) ([a6ac94f](https://github.com/oscnord/FramePeek/commit/a6ac94f3bebecde8d9c1524aad3f44f6ce24c0fc))
* harden the embedded REST server ([#25](https://github.com/oscnord/FramePeek/issues/25)) ([d911605](https://github.com/oscnord/FramePeek/commit/d911605ccaf6140710f4a12f9476f629682ed2dc))
* player seek clamping, duplicate setup, per-tick task, timeline guards ([#38](https://github.com/oscnord/FramePeek/issues/38)) ([f7c685e](https://github.com/oscnord/FramePeek/commit/f7c685efc4e1b3b563976d4fea46172c954d55a2))
* stale-task races on file switch, reader teardown, CacheManager off main thread ([#21](https://github.com/oscnord/FramePeek/issues/21)) ([58d12c1](https://github.com/oscnord/FramePeek/commit/58d12c14b51ccfc9951579423ba81edec9ac15ee))
* waveform envelope keeps true peaks from skipped buffers ([#33](https://github.com/oscnord/FramePeek/issues/33)) ([5abdcec](https://github.com/oscnord/FramePeek/commit/5abdcecc96afc3f68688bd1c0b6039a1a010b5c1))


### Performance

* batch AVAsset property loads, stop re-fetching format descriptions ([#22](https://github.com/oscnord/FramePeek/issues/22)) ([fc542ff](https://github.com/oscnord/FramePeek/commit/fc542ff4de02b7ad88f83e504b7f9614f2ec1c9a))
* cache derived chart data instead of recomputing per render ([#23](https://github.com/oscnord/FramePeek/issues/23)) ([69e27e2](https://github.com/oscnord/FramePeek/commit/69e27e22cbaf2ed0d692e9757cb17d91930f26f3))
* isolate hover and playback state from heavy chart redraws ([#37](https://github.com/oscnord/FramePeek/issues/37)) ([be8878b](https://github.com/oscnord/FramePeek/commit/be8878b3d5edc84ace80c51fd8926f200ce7875e))
* parallelize per-frame color analysis and GOP preload ([#28](https://github.com/oscnord/FramePeek/issues/28)) ([9f911d1](https://github.com/oscnord/FramePeek/commit/9f911d1ba44a52782f7154844e8de48877bc6ed7))
* sync analysis reads the video stream once instead of twice ([#32](https://github.com/oscnord/FramePeek/issues/32)) ([762df76](https://github.com/oscnord/FramePeek/commit/762df76661224ff8c329894520e3c9e909dec3fd))
* vectorize color analysis pixel loops with Accelerate ([#30](https://github.com/oscnord/FramePeek/issues/30)) ([31da30b](https://github.com/oscnord/FramePeek/commit/31da30b6e51de64a7b088e0befaa6e5b371efe13))
* zero-copy frame type detection, one shared BitReader ([#34](https://github.com/oscnord/FramePeek/issues/34)) ([c17b51d](https://github.com/oscnord/FramePeek/commit/c17b51dbdf84aad71160ac153d53c028bcbe91f2))


### Refactoring

* Clean up logging, error handling, and AVFoundation helpers ([#11](https://github.com/oscnord/FramePeek/issues/11)) ([1066048](https://github.com/oscnord/FramePeek/commit/1066048c9827782b8e2ccfeb60f322a8aa282ca6))
* consolidate LTTB downsampling into one generic implementation ([#31](https://github.com/oscnord/FramePeek/issues/31)) ([8fe3067](https://github.com/oscnord/FramePeek/commit/8fe3067560e8cd2dc5c230e568d7668e65955735))
* drop 'professional' from color analysis naming ([#26](https://github.com/oscnord/FramePeek/issues/26)) ([0d68199](https://github.com/oscnord/FramePeek/commit/0d681991442c94cb67a7e35ad859621f6ce174fa))
* one shared collect/bucket/emit engine for bitrate extraction ([#36](https://github.com/oscnord/FramePeek/issues/36)) ([0caebd6](https://github.com/oscnord/FramePeek/commit/0caebd6530fad5d65315b1e22d990ddd6a0f0eed))
