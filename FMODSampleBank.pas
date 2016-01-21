unit FMODSampleBank;

interface
uses
	Windows, Messages;

//----------------------------------------------------------------------------------------------------//
type
	TFourCC = array[0..3] of Char;

	TFSoundFlags = record
		name: PChar;
		flag: DWORD;
		info: PChar;
	end;

const
	UNKNOWN_INFO_STR = 'Unknown';

//====================================================================================================//
//                                              FSB 3 & 4                                             //
//====================================================================================================//
const
	FMOD_FSB_NAMELEN		= 30;

type
	{ FSB3 File Header -- 24 bytes }
	FSOUND_FSB_HEADER_3 = packed record
		fileID: TFourCC;
		entries: Integer;
		hdrSizeTotal: Integer;
		dataSizeTotal: Integer;
		version: DWORD;
		flags: DWORD;
	end;

	{ FSB4 File Header -- 48 bytes }
	FSOUND_FSB_HEADER_4 = packed record
		fileID: TFourCC;
		entries: Integer;
		hdrSize: Integer;
		dataSize: Integer;
		version: DWORD;
		flags: DWORD;
		zero: array[0..7] of Char;
		hash: array[0..15] of Byte;
	end;

	{ FSB Sample Entry -- 80 bytes }
	FSOUND_FSB_SAMPLE_HEADER_3_1 = packed record
		entrySize: Word;	// always 80
		filename: array[0..FMOD_FSB_NAMELEN - 1] of Char;
		samples: DWORD;
		size: DWORD;

		loopStart: DWORD;
		loopEnd: DWORD;
		mode: DWORD;
		freq: Integer;
		defVol: Word;
		defPan: Smallint;
		defPri: Word;
		channels: Word;

		minDistance: Single;
		maxDistance: Single;
		varFreq: Integer;
		varVol: Word;
		varPan: Smallint;
	end;

	{ FSB Basic Sample Header -- 08 bytes }
	FSOUND_FSB_SAMPLE_HEADER_BASIC = packed record
		lengthSamples: DWORD;
		lengthCompressedBytes: DWORD;
	end;

// These flags are used for FMOD_FSB_HEADER::mode */
const
	FMOD_FSB_SOURCE_FORMAT			= $00000001;  // all samples stored in their original compressed format */
	FMOD_FSB_SOURCE_BASICHEADERS	= $00000002;  // samples should use the basic header structure */
	FMOD_FSB_SOURCE_ENCRYPTED		= $00000004;  // all sample data is encrypted */
	FMOD_FSB_SOURCE_BIGENDIANPCM	= $00000008;  // pcm samples have been written out in big-endian format */
	FMOD_FSB_SOURCE_NOTINTERLEAVED	= $00000010;  // Sample data is not interleaved. */
	FMOD_FSB_SOURCE_MPEG_PADDED		= $00000020;  // Mpeg frames are now rounded up to the nearest 2 bytes for normal sounds, or 16 bytes for multichannel. */
	FMOD_FSB_SOURCE_MPEG_PADDED4	= $00000040;  // Mpeg frames are now rounded up to the nearest 4 bytes for normal sounds, or 16 bytes for multichannel. */

const
	FSB_HEADER_FLAGS: array[0..6] of TFSoundFlags = (
		( name: 'FMOD_FSB_SOURCE_FORMAT'; flag: FMOD_FSB_SOURCE_FORMAT; info: 'Samples stored in original compressed format' ),
		( name: 'FMOD_FSB_SOURCE_BASICHEADERS'; flag: FMOD_FSB_SOURCE_BASICHEADERS; info: 'Samples have basic headers' ),
		( name: 'FMOD_FSB_SOURCE_ENCRYPTED'; flag: FMOD_FSB_SOURCE_ENCRYPTED; info: 'Sample data has been encrypted' ),
		( name: 'FMOD_FSB_SOURCE_BIGENDIANPCM'; flag: FMOD_FSB_SOURCE_BIGENDIANPCM; info: 'PCM data is stored in big-endian byte order' ),
		( name: 'FMOD_FSB_SOURCE_NOTINTERLEAVED'; flag: FMOD_FSB_SOURCE_NOTINTERLEAVED; info: 'Sample data is not interleaved' ),
		( name: 'FMOD_FSB_SOURCE_MPEG_PADDED'; flag: FMOD_FSB_SOURCE_MPEG_PADDED; info: 'MPEG frames are aligned to the nearest 2 bytes, 16 bytes for multichannel (Use Frame Verification option)' ),
		( name: 'FMOD_FSB_SOURCE_MPEG_PADDED4'; flag: FMOD_FSB_SOURCE_MPEG_PADDED4; info: 'MPEG frames are aligned to the nearest 4 bytes, 16 bytes for multichannel (Use Frame Verification option)' )
	);

// FSB3&4 Sample Mode Flags
// FMOD 3 defines.  These flags are used for FMOD_FSB_SAMPLE_HEADER::mode */
const
	FSOUND_LOOP_OFF              = $00000001;  // For non looping samples. */
	FSOUND_LOOP_NORMAL           = $00000002;  // For forward looping samples. */
	FSOUND_LOOP_BIDI             = $00000004;  // For bidirectional looping samples.  (no effect if in hardware). */
	FSOUND_8BITS                 = $00000008;  // For 8 bit samples. */
	FSOUND_16BITS                = $00000010;  // For 16 bit samples. */
	FSOUND_MONO                  = $00000020;  // For mono samples. */
	FSOUND_STEREO                = $00000040;  // For stereo samples. */
	FSOUND_UNSIGNED              = $00000080;  // For user created source data containing unsigned samples. */
	FSOUND_SIGNED                = $00000100;  // For user created source data containing signed data. */
	FSOUND_MPEG                  = $00000200;  // For MPEG layer 2/3 data. */
	FSOUND_CHANNELMODE_ALLMONO   = $00000400;  // Sample is a collection of mono channels. */
	FSOUND_CHANNELMODE_ALLSTEREO = $00000800;  // Sample is a collection of stereo channel pairs */
	FSOUND_HW3D                  = $00001000;  // Attempts to make samples use 3d hardware acceleration. (if the card supports it) */
	FSOUND_2D                    = $00002000;  // Tells software (not hardware) based sample not to be included in 3d processing. */
	FSOUND_SYNCPOINTS_NONAMES    = $00004000;  // Specifies that syncpoints are present with no names */
	FSOUND_DUPLICATE             = $00008000;  // This subsound is a duplicate of the previous one i.e. it uses the same sample data but w/different mode bits */
	FSOUND_CHANNELMODE_PROTOOLS  = $00010000;  // Sample is 6ch and uses L C R LS RS LFE standard. */
	FSOUND_MPEGACCURATE          = $00020000;  // For FSOUND_Stream_Open - for accurate FSOUND_Stream_GetLengthMs/FSOUND_Stream_SetTime.  WARNING, see FSOUND_Stream_Open for inital opening time performance issues. */
	FSOUND_HW2D                  = $00080000;  // 2D hardware sounds.  allows hardware specific effects */
	FSOUND_3D                    = $00100000;  // 3D software sounds */
	FSOUND_32BITS                = $00200000;  // For 32 bit (float) samples. */
	FSOUND_IMAADPCM              = $00400000;  // Contents are stored compressed as IMA ADPCM */
	FSOUND_VAG                   = $00800000;  // For PS2 only - Contents are compressed as Sony VAG format */
	FSOUND_XMA                   = $01000000;  // For Xbox360 only - Contents are compressed as XMA format */
	FSOUND_GCADPCM               = $02000000;  // For Gamecube only - Contents are compressed as Gamecube DSP-ADPCM format */
	FSOUND_MULTICHANNEL          = $04000000;  // For PS2 and Gamecube only - Contents are interleaved into a multi-channel (more than stereo) format */
	FSOUND_OGG                   = $08000000;  // For vorbis encoded ogg data */
	FSOUND_CELT                  = $08000000;  // For vorbis encoded ogg data */
	FSOUND_MPEG_LAYER3           = $10000000;  // Data is in MP3 format. */
	FSOUND_MPEG_LAYER2           = $00040000;  // Data is in MP2 format. */
	FSOUND_LOADMEMORYIOP         = $20000000;  // For PS2 only - "name" will be interpreted as a pointer to data for streaming and samples.  The address provided will be an IOP address */
	FSOUND_IMAADPCMSTEREO        = $20000000;  // Signify IMA ADPCM is actually stereo not two interleaved mono */
	FSOUND_IGNORETAGS            = $40000000;  // Skips id3v2 etc tag checks when opening a stream, to reduce seek/read overhead when opening files (helps with CD performance) */
	FSOUND_SYNCPOINTS            = $80000000;  // Specifies that syncpoints are present */

const
	FSOUND_SAMPLE_FLAGS: array[0..32] of TFSoundFlags = (
		( name: 'FSOUND_LOOP_OFF'; flag: FSOUND_LOOP_OFF; info: UNKNOWN_INFO_STR ),
		( name: 'FSOUND_LOOP_NORMAL'; flag: FSOUND_LOOP_NORMAL; info: UNKNOWN_INFO_STR ),
		( name: 'FSOUND_LOOP_BIDI'; flag: FSOUND_LOOP_BIDI; info: UNKNOWN_INFO_STR ),
		( name: 'FSOUND_8BITS'; flag: FSOUND_8BITS; info: 'Uses 8-bits per sample' ),
		( name: 'FSOUND_16BITS'; flag: FSOUND_16BITS; info: 'Uses 16-bits per sample' ),
		( name: 'FSOUND_MONO'; flag: FSOUND_MONO; info: 'Sample has ONE channel' ),
		( name: 'FSOUND_STEREO'; flag: FSOUND_STEREO; info: 'Sample has TWO channels' ),
		( name: 'FSOUND_UNSIGNED'; flag: FSOUND_UNSIGNED; info: UNKNOWN_INFO_STR ),
		( name: 'FSOUND_SIGNED'; flag: FSOUND_SIGNED; info: UNKNOWN_INFO_STR ),
		( name: 'FSOUND_MPEG'; flag: FSOUND_MPEG; info: 'Sample is stored in MPEG format' ),
		( name: 'FSOUND_CHANNELMODE_ALLMONO'; flag: FSOUND_CHANNELMODE_ALLMONO; info: 'Sample is a collection of mono channels' ),
		( name: 'FSOUND_CHANNELMODE_ALLSTEREO'; flag: FSOUND_CHANNELMODE_ALLSTEREO; info: 'Sample is a collection of stereo channel pairs' ),
		( name: 'FSOUND_HW3D'; flag: FSOUND_HW3D; info: UNKNOWN_INFO_STR ),
		( name: 'FSOUND_2D'; flag: FSOUND_2D; info: 'Not included in 3D processing' ),
		( name: 'FSOUND_SYNCPOINTS_NONAMES'; flag: FSOUND_SYNCPOINTS_NONAMES; info: UNKNOWN_INFO_STR ),
		( name: 'FSOUND_DUPLICATE'; flag: FSOUND_DUPLICATE; info: UNKNOWN_INFO_STR ),
		( name: 'FSOUND_CHANNELMODE_PROTOOLS'; flag: FSOUND_CHANNELMODE_PROTOOLS; info: UNKNOWN_INFO_STR ),
		( name: 'FSOUND_MPEGACCURATE'; flag: FSOUND_MPEGACCURATE; info: UNKNOWN_INFO_STR ),
		( name: 'FSOUND_HW2D'; flag: FSOUND_HW2D; info: UNKNOWN_INFO_STR ),
		( name: 'FSOUND_3D'; flag: FSOUND_3D; info: UNKNOWN_INFO_STR ),
		( name: 'FSOUND_32BITS'; flag: FSOUND_32BITS; info: 'Uses 32-bits per sample' ),
		( name: 'FSOUND_IMAADPCM'; flag: FSOUND_IMAADPCM; info: 'Sample is stored in ADPCM format' ),
		( name: 'FSOUND_VAG'; flag: FSOUND_VAG; info: UNKNOWN_INFO_STR ),
		( name: 'FSOUND_XMA'; flag: FSOUND_XMA; info: UNKNOWN_INFO_STR ),
		( name: 'FSOUND_GCADPCM'; flag: FSOUND_GCADPCM; info: UNKNOWN_INFO_STR ),
		( name: 'FSOUND_MULTICHANNEL'; flag: FSOUND_MULTICHANNEL; info: 'Sample contains multiple interleaved channels' ),
		( name: 'FSOUND_OGG'; flag: FSOUND_OGG; info: 'Samples are stored in Ogg/CELT format' ),
		( name: 'FSOUND_MPEG_LAYER3'; flag: FSOUND_MPEG_LAYER3; info: 'Samples are stored in MPEG Layer 3 format' ),
		( name: 'FSOUND_MPEG_LAYER2'; flag: FSOUND_MPEG_LAYER2; info: UNKNOWN_INFO_STR ),
		( name: 'FSOUND_LOADMEMORYIOP'; flag: FSOUND_LOADMEMORYIOP; info: 'PS2 only flag that specifies the name to be a pointer to data for streaming and samples' ),
		( name: 'FSOUND_IMAADPCMSTEREO'; flag: FSOUND_IMAADPCMSTEREO; info: 'IMAADPCM is stereo and not two interleaved mono samples' ),
		( name: 'FSOUND_IGNORETAGS'; flag: FSOUND_IGNORETAGS; info: UNKNOWN_INFO_STR ),
		( name: 'FSOUND_SYNCPOINTS'; flag: FSOUND_SYNCPOINTS; info: UNKNOWN_INFO_STR )
	);

//====================================================================================================//
//                                                 FSB5                                               //
//====================================================================================================//
type
	{ FSB5: 60/64 bytes? }
	FSB_HEADER_5 = packed record
		fileID: TFourCC;
		version: DWORD;
		entries: DWORD;
		infoSizeTotal: DWORD;
		nameSizeTotal: DWORD;
		dataSizeTotal: DWORD;
		formatId: DWORD;
		zero: array[0..7] of Char;
		hash: array[0..15] of Char;
		dummy: array[0..7] of Char;
	end;

// FSB5 Sample Format -- Az: WIP
const
	FSB5_SAMPLE_FORMAT_UNKNOWN	= 0;
	FSB5_SAMPLE_FORMAT_PCM8		= 1;
	FSB5_SAMPLE_FORMAT_PCM16	= 2;
	FSB5_SAMPLE_FORMAT_PCM24	= 3;
	FSB5_SAMPLE_FORMAT_ADPCM	= 7;
	FSB5_SAMPLE_FORMAT_XMA		= 10;
	FSB5_SAMPLE_FORMAT_MPEG		= 11;
	FSB5_SAMPLE_FORMAT_CELT		= 12;
	FSB5_SAMPLE_FORMAT_VORBIS	= 15;

//	FSB5_01_COMPRESSED 	= $01;		// Compressed?
//	FSB5_02_UNKNOWN	  	= $02;		// Unknown
//	FSB5_04_ADPCM		= $04;		// Samples are stored in ADPCM format
//	FSB5_08_MPEG		= $08;		// Samples are stored in MPEG format
//	FSB5_10_UNKNOWN		= $10;		//

//	FSB5_HEADER_FLAGS: array[0..4] of TFSoundFlags = (
//  		( name: 'FSB5_01'; flag: FSB5_01_COMPRESSED; info: 'Compressed?' ),
//		( name: 'FSB5_02'; flag: FSB5_02_UNKNOWN; info: UNKNOWN_INFO_STR ),
//		( name: 'FSB5_ADPCM'; flag: FSB5_04_ADPCM; info: 'Samples are stored in ADPCM format' ),
//		( name: 'FSB5_MPEG'; flag: FSB5_08_MPEG; info: 'Samples are stored in MPEG format' ),
//		( name: 'FSB5_10'; flag: FSB5_10_UNKNOWN; info: UNKNOWN_INFO_STR )
//	);

// FSB5 Sample Flags -- Az: WIP
const
	FSB5_SAMPLE_EXTRAPARAMS	  		= $01;		// The sample has extra parameters, such as loop info
	FSB5_SAMPLE_02					= $02;		// [seen in planetside2, mechwarrior]
	FSB5_SAMPLE_04					= $04;		// [seen in planetside2, mechwarrior]
	FSB5_SAMPLE_08					= $08;		// [seen in planetside2]
	FSB5_SAMPLE_DELTA				= $10;		// MPEG frames are aligned to 32 byte borders
	FSB5_SAMPLE_STEREO				= $20;		// Sample has TWO channels
	FSB5_SAMPLE_40					= $40;		// Invalid flag? We only use 6 bits now (Maybe it's 7?)

const
	FSB5_SAMPLE_FLAGS: array[0..6] of TFSoundFlags = (
		( name: 'FSB5_SAMPLE_EXTRAPARAMS'; flag: FSB5_SAMPLE_EXTRAPARAMS; info: 'The sample has extra parameters, such as loop info' ),
		( name: 'FSB5_SAMPLE_02'; flag: FSB5_SAMPLE_02; info: UNKNOWN_INFO_STR ),
		( name: 'FSB5_SAMPLE_04'; flag: FSB5_SAMPLE_04; info: UNKNOWN_INFO_STR ),
		( name: 'FSB5_SAMPLE_08'; flag: FSB5_SAMPLE_08; info: UNKNOWN_INFO_STR ),
//		( name: 'FSB5_SAMPLE_MPEG_PADDED4'; flag: FSB5_SAMPLE_DELTA; info: 'MPEG frames are aligned to nearest 4 byte (Use Frame Verification option)' ),
		( name: 'FSB5_SAMPLE_10'; flag: FSB5_SAMPLE_DELTA; info: UNKNOWN_INFO_STR ),	// might be multi channel stuff, not sure???
		( name: 'FSB5_SAMPLE_STEREO'; flag: FSB5_SAMPLE_STEREO; info: 'Sample has TWO channels' ),
		( name: 'FSB5_SAMPLE_40'; flag: FSB5_SAMPLE_40; info: UNKNOWN_INFO_STR )	// invalid flag
	);

// FSB5 extraType ID
const
	FSB5_EXTRA_CHANNEL		= 1;
	FSB5_EXTRA_FREQ			= 2;
	FSB5_EXTRA_LOOP			= 3;

//----------------------------------------------------------------------------------------------------//
implementation
end.
