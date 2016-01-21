unit FsbReaderClass;

interface
uses
	Windows, SysUtils, Graphics,
	AzLib, FileIOClass, MpegAudio, FMODSampleBank,
	EventLogger,	// Az: remove this?
	Math, MMSystem;

//----------------------------------------------------------------------------------------------------//
const
	{ wave header formats }
	WAVE_FORMAT_NONE	= 0;
	WAVE_FORMAT_PCM		= 1;
	WAVE_FORMAT_FLOAT	= 3;
	WAVE_FORMAT_ADPCM	= 17;	// 105 for the xbox type?
	WAVE_FORMAT_XMA		= 105;
	WAVE_FORMAT_MP3		= 85;
	WAVE_FORMAT_VORBIS	= 26447;

	{ custom event logger flags  - Az: these flags shouldn't really be in this unit }
	LOG_MSGBOX_INFO		= LOG_USER shl 0;	// the added text will also show to the user through a messagebox
	LOG_MSGBOX_WARN		= LOG_USER shl 1;	// - as warning
	LOG_MSGBOX_ERROR	= LOG_USER shl 2;	// - as error

type
	{ Internal header info storage }
	TFsbHeaderInfo = record
		FileID: TFourCC;
		version: DWORD;
		entries: DWORD;
		flags: DWORD;
		headerSize: Integer;
		dataSize: Integer;
	end;

	{ Internal sample data storage }
	PFsbSampleEntry = ^TFsbSampleEntry;
	TFsbSampleEntry = record
		samplename: array[0..63] of Char;
		hdrOffset: LongWord;
		hdrSize: LongWord;
		dataOffset: LongWord;
		dataSize: LongWord;
		samples: LongWord;
		flags: LongWord;
		channels: Word;
		freq: LongWord;
		loopStart, loopEnd: Integer;
		{ fsb3&4 extra params }
		defVol: Word;
		defPan: Smallint;
		defPri: Word;
		minDistance: Single;
		maxDistance: Single;
		varFreq: Integer;
		varVol: Word;
		varPan: Smallint;
		{ not part of sample header }
		bitsPerSample: Single;
		format: Word;
	end;
	TFsbSampleList = array of TFsbSampleEntry;

	{ Callback function used to call owner about details regarding reading the samples }
	TOnLogEvent = procedure(Sender: TObject; const Text: string; Indent: Integer; Color: Integer; Flags: LongWord) of object;
	TOnScanUpdate = function(Sender: TObject; FilePos: LongWord; Buffer: PChar; BufLength: LongWord):Boolean of object;

	{ FSB Reader Class }
	TFsbReaderClass = class
	private
		fFsbFile: TFileIOClass;
		fFileName: string;
		fFileSize: LongWord;
		fFileOffset: Integer;
		fHeader: TFsbHeaderInfo;
		fSamples: TFsbSampleList;
		fToken: TFourCC;
		fMajorVersion: Byte;
		fLogVerbose: Boolean;
		fOnLogEvent, fOnLogExtractEvent: TOnLogEvent;
		fOnScanUpdate: TOnScanUpdate;
		{ props }
		procedure SetFileOffset(Value: Integer);
		function GetToken():TFourCC;
		function GetMajorVersion():Byte;
		{ misc }
		procedure ResetProperties();
		procedure ReadHeaderToken();
		{ private }
		function LoadFsb3And4():Boolean;
		function LoadFsb5():Boolean;
		function CorrectFrameAlignment(Buffer: PChar; BufSize: Integer; SampleSize, SampleCount: LongWord): LongWord;
		function WriteWaveHeader(Output: TFileIOClass; Entry: PFsbSampleEntry):Word;
		procedure WriteWaveHeaderFinalize(Output: TFileIOClass; Entry: PFsbSampleEntry);
	public
		constructor Create();
		destructor Destroy(); override;
		{ public }
		function OpenFsb(const FileName: string):Boolean;
		function CloseFsb():Boolean;
		function FindHeaderOffset(StartOffset: Integer; MaxRange: Integer = -1):Integer;
		function GetExtensionByFormat(FormatID: Word):string;
		function GetSampleFormatName(FormatID: Word):string;
		function LoadFsbSamples():Boolean;
		function PeekAtHeader():Boolean;
		function GetUniqueSampleFileName(Index: Integer; AddFileExt: Boolean): string;
		function ExtractSampleEntry(Index: Integer; const FileName: string; AddWaveHeader, MP3FrameVerification: Boolean):Boolean;
		{ props }
		property FileName: string read fFileName;
		property FileSize: LongWord read fFileSize;
		property Offset: Integer read fFileOffset write SetFileOffset;
		property Header: TFsbHeaderInfo read fHeader;
		property Samples: TFsbSampleList read fSamples;

		property Token: TFourCC read GetToken;
		property MajorVersion: Byte read GetMajorVersion;

		property VerboseLogging: Boolean read fLogVerbose write fLogVerbose;
		property OnLogEvent: TOnLogEvent read fOnLogEvent write fOnLogEvent;
		property OnLogExtractEvent: TOnLogEvent read fOnLogExtractEvent write fOnLogExtractEvent;
		property OnScanUpdate: TOnScanUpdate read fOnScanUpdate write fOnScanUpdate;
	end;

//----------------------------------------------------------------------------------------------------//
implementation

//====================================================================================================//
//                                          Create & Destroy                                          //
//====================================================================================================//
constructor TFsbReaderClass.Create();
begin
	fFsbFile := TFileIOClass.Create();
	fLogVerbose := false;
	CloseFsb();
	ResetProperties();
end;
//----------------------------------------------------------------------------------------------------//
destructor TFsbReaderClass.Destroy();
begin
	CloseFsb();
	fFsbFile.Free();
	inherited;
end;
//====================================================================================================//
//                                    Property Read/Write Functions                                   //
//====================================================================================================//
procedure TFsbReaderClass.SetFileOffset(Value: Integer);
begin
	if (Value = fFileOffset) then
		Exit;
	//ResetProperties();	//Az: should really be called right? if not the samples are not cleared when scanning a multi fsb container
	fFileOffset := Value;
	fFsbFile.Pos := fFileOffset;
end;
//----------------------------------------------------------------------------------------------------//
function TFsbReaderClass.GetToken():TFourCC;
begin
	if (fFileName <> '') and (fToken = '') then begin
		ReadHeaderToken();
	end;
	Result := fToken;
end;
//----------------------------------------------------------------------------------------------------//
function TFsbReaderClass.GetMajorVersion():Byte;
begin
	if (fFileName <> '') and (fToken = '') then begin
		ReadHeaderToken();
	end;
	Result := fMajorVersion;
end;
//====================================================================================================//
//                                              Private                                               //
//====================================================================================================//
procedure TFsbReaderClass.ResetProperties();
begin
	fToken := '';
	fMajorVersion := 0;
	fSamples := nil;
	FillChar(fHeader,SizeOf(fHeader),0);
end;
//----------------------------------------------------------------------------------------------------//
procedure TFsbReaderClass.ReadHeaderToken();
var
	bytesRead: Integer;
begin
	bytesRead := fFsbFile.Read(SizeOf(fToken),@fToken);
	if (bytesRead = SizeOf(fToken)) and (fToken[0] = 'F') and (fToken[1] = 'S') and (fToken[2] = 'B') and (fToken[3] in ['1'..'9']) then
		fMajorVersion := Ord(fToken[3]) - Ord('0')
	else
		fMajorVersion := 0;
	fFsbFile.Pos := fFileOffset;
end;
//----------------------------------------------------------------------------------------------------//
// Removes the alignment from the MP3 frames in the buffer so it can be played correctly.             //
// Returns the correct size of the buffer, i.e, the size of the buffer which contains valid frames.   //
// Example: The League of Legend MP3 frames are aligned to 4 bytes.                                   //
// If a frame is found near the end of the buffer, only the part inside the buffer is corrected for.  //
// It appears sample data can actually extend beyond the specified DataSize in some FSBs.             //
function TFsbReaderClass.CorrectFrameAlignment(Buffer: PChar; BufSize: Integer; SampleSize: LongWord; SampleCount: LongWord):LongWord;
var
	pos, posCorrect: Integer;
	frame: TMpegAudioFrame;
	frameData: TMpegFrameData;
	samplesWritten: LongWord;
begin
	pos := 0;
	posCorrect := 0;
	samplesWritten := 0;
	while (pos < BufSize - SizeOf(TMpegAudioFrame)) do begin
		frame := AzSwapEndian32(PDWORD(@Buffer[pos])^);
		{ if invalid frame, increase read pos by one and try again }
		if not (MP3_AnalyzeFrame(frame,frameData)) then begin
			Inc(pos);
			Continue;
		end;
		{ decrease frame size if it would extend beyond bufsize }
		if (pos + frameData.FrameSize > BufSize) then
			frameData.FrameSize := (BufSize - pos);
		{ if misaligned, move the frame back down to the correct position }
		if (pos <> posCorrect) then
			Move(Buffer[pos],Buffer[posCorrect],frameData.FrameSize);
		{ increase positions before next frame }
		Inc(pos,frameData.FrameSize);
		Inc(posCorrect,frameData.FrameSize);
		Inc(samplesWritten,frameData.SampleCount);
		{ break here if we're written enough samples OR data }
		if (samplesWritten >= SampleCount) or (posCorrect > Integer(SampleSize)) then begin
			Break;
		end;
	end;
	Result := posCorrect;
end;
//====================================================================================================//
//                                               Public                                               //
//====================================================================================================//
function TFsbReaderClass.OpenFsb(const FileName: string):Boolean;
begin
	CloseFsb();
	Result := fFsbFile.OpenFile(FileName,fmOpenRead or fmShareDenyNone);
	if (Result) then begin
		fFileName := FileName;
		fFileSize := fFsbFile.Size;
	end;
end;
//----------------------------------------------------------------------------------------------------//
function TFsbReaderClass.CloseFsb():Boolean;
begin
	fFileName := '';
	fFileSize := 0;
	fFileOffset := 0;
	ResetProperties();
	Result := fFsbFile.CloseFile();
end;
//----------------------------------------------------------------------------------------------------//
// Scans the file for any matching pattern of "FSB1..9".                                              //
function TFsbReaderClass.FindHeaderOffset(StartOffset: Integer; MaxRange: Integer):Integer;
const
	BUFSIZE = 1024 * 16;
	STR_MATCH = 'FSB';
var
	buf: array[0..BUFSIZE - 1] of Char;
	i, bytesRead, matchCount, fPos: Integer;
begin
	Result := -1;
	if (StartOffset < 0) then
		Exit;
	if (MaxRange = -1) then
		MaxRange := fFileSize;
	matchCount := 0;
	fPos := StartOffset;
	fFsbFile.Pos := fPos;
	while (Result = -1) and (MaxRange > 0) do begin
		bytesRead := fFsbFile.Read(Min(BUFSIZE,MaxRange),@buf);
		if (bytesRead = 0) or (@fOnScanUpdate <> nil) and not (fOnScanUpdate(Self,fPos,buf,bytesRead)) then
			Break;
		for i := 0 to bytesRead - 1 do begin
			if (matchCount = 3) then begin
				if (buf[i] in ['3'..'5']) then begin	// only 3 to 5 supported
					Result := (fPos + i - 3);
					Break;
				end
				else
					matchCount := 0;
			end
			else if (buf[i] = STR_MATCH[matchCount + 1]) then
				Inc(matchCount)
			else
				matchCount := 0;
		end;
		Dec(MaxRange,bytesRead);
		Inc(fPos,bytesRead);
	end;
	fFsbFile.Pos := fFileOffset;
end;
//----------------------------------------------------------------------------------------------------//
function TFsbReaderClass.GetExtensionByFormat(FormatID: Word): string;
begin
	case FormatID of
	FSB5_SAMPLE_FORMAT_PCM16, FSB5_SAMPLE_FORMAT_ADPCM: Result := '.wav';
	FSB5_SAMPLE_FORMAT_XMA:		Result := '.xma';
	FSB5_SAMPLE_FORMAT_MPEG:	Result := '.mp3';
	FSB5_SAMPLE_FORMAT_CELT:	Result := '.celt';
	FSB5_SAMPLE_FORMAT_VORBIS:	Result := '.ogg';
	else
		Result := '.raw';
	end;
end;
//----------------------------------------------------------------------------------------------------//
function TFsbReaderClass.GetSampleFormatName(FormatID: Word):string;
begin
	case FormatID of
	FSB5_SAMPLE_FORMAT_UNKNOWN:	Result := 'Unknown';
	FSB5_SAMPLE_FORMAT_PCM16:	Result := 'PCM';
	FSB5_SAMPLE_FORMAT_ADPCM:	Result := 'ADPCM';
	FSB5_SAMPLE_FORMAT_XMA:		Result := 'XMA';
	FSB5_SAMPLE_FORMAT_MPEG:	Result := 'MP3';
	FSB5_SAMPLE_FORMAT_CELT:	Result := 'Celt';
	FSB5_SAMPLE_FORMAT_VORBIS:	Result := 'Vorbis';
	else
		Result := Format('Unknown (%d)',[FormatID]);
	end;
end;
//----------------------------------------------------------------------------------------------------//
// Reads the headers of the opened FSB file.                                                          //
function TFsbReaderClass.PeekAtHeader():Boolean;
begin
	Result := false;
	if not (fFsbFile.IsOpen) then
		Exit;
	{ read }
	FillChar(fHeader,SizeOf(fHeader),0);
	fFsbFile.Read(SizeOf(TFourCC),@fHeader.FileID);
	if (fHeader.FileID = 'FSB3') or (fHeader.FileID = 'FSB4') then begin
		fHeader.entries := fFsbFile.ReadInt32();
		fFsbFile.Pos := fFileOffset + 16;
		fHeader.version := fFsbFile.ReadInt32();
		fHeader.flags := fFsbFile.ReadInt32();
		Result := true;
	end
	else if (fHeader.FileID = 'FSB5') then begin
		fHeader.version := fFsbFile.ReadInt32();
		fHeader.entries := fFsbFile.ReadInt32();
		fFsbFile.Pos := fFileOffset + 24;
		fHeader.flags := fFsbFile.ReadInt32();		// formatID
		Result := true;
	end
	else
		Result := false;
	{ end }
	fFsbFile.Pos := fFileOffset;
end;
//----------------------------------------------------------------------------------------------------//
// Generates a unique filename from the samplename, and file extension if desired.                    //
// If several samples have the same name, the filename is appended with an index to avoid conflict    //
function TFsbReaderClass.GetUniqueSampleFileName(Index: Integer; AddFileExt: Boolean):string;
var
	i, dupCount: Integer;
	sample: PFsbSampleEntry;
	fileExt: string;
begin
	sample := @fSamples[Index];
	Result := sample^.samplename;
	{ Determine file extension }
	if (AddFileExt) then begin
		fileExt := GetExtensionByFormat(sample^.format);
		{ Strip the file extension from the samplename if it already have one. Doing this allows us to add duplicate indication if needed }
		if (SameText(fileExt,Copy(Result,Length(Result) - Length(fileExt) + 1,Length(fileExt)))) then
			SetLength(Result,Length(Result) - Length(fileExt));
	end
	else
		fileExt := '';
	{ Avoid Duplicate Names }
	dupCount := 0;
	for i := 0 to Index - 1 do begin
		if (SameText(sample^.samplename,fSamples[i].samplename)) then
			Inc(dupCount);
	end;
	if (dupCount > 0) then begin
		Result := Format('%s (%d)',[Result,dupCount + 1]);
		if (fLogVerbose) and (@fOnLogExtractEvent <> nil) then
			fOnLogExtractEvent(Self,Format('Duplicate samplename was found; extracted filename has been tagged (%d) to avoid conflict',[dupCount + 1]),1,clPurple,0);
	end;
	{ Add file extension }
	if (fileExt <> '') then
		Result := Result + fileExt;
end;
//----------------------------------------------------------------------------------------------------//
function TFsbReaderClass.ExtractSampleEntry(Index: Integer; const FileName: string; AddWaveHeader, MP3FrameVerification: Boolean):Boolean;
var
	bytesRead, bytesToWrite, diff, bufSize: Integer;
	waveFormatId: Word;
	buf: PChar;
	entry: PFsbSampleEntry;
	output: TFileIOClass;
begin
	Result := false;
	entry := @fSamples[Index];
	{ Check for reasons why we cannot extract the sample }
	if (entry^.dataSize <= 0) then begin
		if (@fOnLogExtractEvent <> nil) then
			fOnLogExtractEvent(Self,Format('Failed to extract sample, because it has no data. [%.2d]: "%s"',[Index,entry^.samplename]),0,clRed,LOG_BOLD or LOG_MSGBOX_ERROR);
		Exit;
	end
	else if (entry^.dataOffset > fFileSize) or (entry^.dataSize > fFileSize) then begin
		if (@fOnLogExtractEvent <> nil) then begin
			fOnLogExtractEvent(Self,Format('Failed to extract sample, as the data offset points outside file boundries. [%.2d]: "%s"',[Index,entry^.samplename]),0,clRed,LOG_BOLD or LOG_MSGBOX_ERROR);
			fOnLogExtractEvent(Self,Format('Filesize: %.0n  |  Offset: %.0n  |  Datasize: %.0n',[fFileSize / 1,entry^.dataOffset / 1,entry^.dataSize / 1]),1,clRed,0);
		end;
		Exit;
	end;
	{ Extract }
	buf := nil;
	bufSize := 0;
	output := TFileIOClass.Create();
	try
		if not (output.CreateFile(FileName,true)) then
			Exit;
		bufSize := entry^.dataSize * 1;		// Az: Aligned streaming files can extend beyond DataSize for some strange reason. Use the next samples offset to check real size?
		GetMem(buf,bufSize);
		{ Read }
		fFsbFile.Pos := entry^.dataOffset;
		bytesRead := fFsbFile.Read(bufSize,buf);
		if (bytesRead <> bufSize) and (@fOnLogExtractEvent <> nil) then begin
			diff := (bufSize - bytesRead);
			fOnLogExtractEvent(Self,Format('Could only read %.0n bytes out of %.0n. Difference of %.0n bytes (%.3f%%).',[bytesRead / 1,bufSize / 1,diff / 1,diff / bufSize * 100]),1,clRed,0);
		end;
		{ Write WAVE header }
		AddWaveHeader := (AddWaveHeader) and (entry^.format <> FSB5_SAMPLE_FORMAT_MPEG) and (entry^.format <> FSB5_SAMPLE_FORMAT_VORBIS);
		if (AddWaveHeader) then begin
			waveFormatId := WriteWaveHeader(output,entry);
			if (@fOnLogExtractEvent <> nil) and (fLogVerbose) then
				fOnLogExtractEvent(Self,Format('Wrote WAVE header with format %s (%d)',[GetSampleFormatName(entry^.format),waveFormatId]),1,clGreen,0);
		end;
		{ Write Data }
		bytesToWrite := bytesRead;
		if (entry^.format = FSB5_SAMPLE_FORMAT_MPEG) and (MP3FrameVerification) then begin
			bytesToWrite := CorrectFrameAlignment(buf,bytesRead,entry^.dataSize,entry^.samples);
		end;
		output.Write(bytesToWrite,buf);
		{ Write WAVE header -- Finalize by updating totals and odd padding }
		if (AddWaveHeader) then
			WriteWaveHeaderFinalize(output,entry);
		{ SUCCESS }
		if (@fOnLogExtractEvent <> nil) then begin
			fOnLogExtractEvent(Self,Format('File successfully extracted  ->  %s  (%.0n bytes)',[FileName,output.Pos / 1]),0,clBlack,LOG_BOLD);
			if (@fOnLogExtractEvent <> nil) and (fLogVerbose) and (bytesToWrite <> bytesRead) then begin
				diff := (bytesToWrite - Integer(entry^.dataSize));
				fOnLogExtractEvent(Self,Format('MP3 Frame Verifier: Wrote %.0n bytes instead of %.0n bytes. Difference of %.n bytes (%.2f%%).',[bytesToWrite / 1,entry^.dataSize / 1,diff / 1,diff / entry^.dataSize * 100]),1,clPurple,0);
			end;
		end;
		Result := true;
	finally
		FreeMem(buf,bufSize);
		fFsbFile.Pos := fFileOffset;
		output.CloseFile();
		output.Free();
	end;
end;
//====================================================================================================//
//                                            Wave Header                                             //
//====================================================================================================//
// Writes WAVE header the the output file. Call WriteWaveHeaderFinalize() when done.                  //
// IMA ADPCM: https://www.icculus.org/SDL_sound/downloads/external_documentation/wavecomp.htm         //
function TFsbReaderClass.WriteWaveHeader(Output: TFileIOClass; Entry: PFsbSampleEntry):Word;
var
	hWave: tWAVEFORMATEX;
	//hWaveAd: ADPCMWAVEFORMAT;
	//x, y: Integer;
begin
	{ Wave Header Format ID }
	case entry^.format of
	FSB5_SAMPLE_FORMAT_PCM16:	hWave.wFormatTag := WAVE_FORMAT_PCM;
	FSB5_SAMPLE_FORMAT_ADPCM:	hWave.wFormatTag := WAVE_FORMAT_ADPCM;
	FSB5_SAMPLE_FORMAT_XMA:		hWave.wFormatTag := WAVE_FORMAT_XMA;
	FSB5_SAMPLE_FORMAT_MPEG:	hWave.wFormatTag := WAVE_FORMAT_MP3;
	FSB5_SAMPLE_FORMAT_CELT,
	FSB5_SAMPLE_FORMAT_VORBIS:	hWave.wFormatTag := WAVE_FORMAT_VORBIS;
	else
		hWave.wFormatTag := 0;
	end;
	{ Fill in Data }
	hWave.nChannels			:= Entry^.channels;
	hWave.nSamplesPerSec	:= Entry^.freq;
	hWave.nAvgBytesPerSec	:= (Entry^.freq * Entry^.channels * Round(Entry^.bitsPerSample) div 8);	// "nAvgBytesPerSec" is calculated from the rounded "bitsPerSample" and not "dataSize / time"
	hWave.nBlockAlign		:= Round(Entry^.bitsPerSample / 8 * Entry^.channels);
	hWave.wBitsPerSample	:= Trunc(Entry^.bitsPerSample);	// Trunc(), not Round()
	hWave.cbSize			:= 0;
	{ Format Specific: Pre-Header }
	if ((fMajorVersion = 3) or (fMajorVersion = 4)) and (Entry^.flags and FSOUND_32BITS > 0) then
		hWave.wFormatTag := WAVE_FORMAT_FLOAT;
	if (hWave.wFormatTag = WAVE_FORMAT_ADPCM) then begin
		Inc(hWave.cbSize,2);
		hWave.nBlockAlign := (36 * hWave.nChannels);	//hWave.nBlockAlign := Round(Entry^.bitsPerSample * Entry^.channels * 8);
//		hWave.nBlockAlign := Trunc(256 * hWave.nChannels * Math.Max(1,hWave.nSamplesPerSec / 11025));
	end;
	{ Write Header }
	Output.WriteStr(4,'RIFF');
	Output.WriteInt32(0);		// We don't know this yet. Updated in WriteWaveHeaderFinalize()
	Output.WriteStr(4,'WAVE');
	Output.WriteStr(4,'fmt ');
	Output.WriteInt32(SizeOf(hWave) + hWave.cbSize);
	Output.Write(SizeOf(hWave),@hWave);
	{ Format Specific: Post-Header }
	if (hWave.wFormatTag = WAVE_FORMAT_ADPCM) then begin
		//x := (hWave.nBlockAlign - (hWave.nChannels * 4)) * 8;
		//y := (hWave.wBitsPerSample * hWave.nChannels);
		//AzFileWriteInt(fOut,2,(x div y) + 1);
		//AzFileWriteInt(fOut,2,$07F9);
		Output.WriteInt16(Entry^.samples div hWave.nBlockAlign);	// wSamplesPerBlock -- Az: This is unlikely to be correct
	end;
	{ Extra Chunks [fact] }
	if (hWave.wFormatTag <> WAVE_FORMAT_PCM) then begin
		Output.WriteStr(4,'fact');
		Output.WriteInt32(4);
		Output.WriteInt32(Entry^.samples);
	end;
	{ Data Chunk }
	Output.WriteStr(4,'data');
	Output.WriteInt32(Entry^.dataSize);
	{ Return Wave Format ID }
	Result := hWave.wFormatTag;
end;
//----------------------------------------------------------------------------------------------------//
// Finalizes the WAVE header by updating total RIFF size and adding a padding byte if data is odd.    //
procedure TFsbReaderClass.WriteWaveHeaderFinalize(Output: TFileIOClass; Entry: PFsbSampleEntry);
var
	outputFileSize: LongWord;
begin
	{ Add odd padding byte }
	if (Entry^.dataSize and 1 = 1) then
		Output.WriteInt8(0);
	{ Write total RIFF header size }
	outputFileSize := LongWord(Output.Pos);
	Output.Pos := 4;
	Output.WriteInt32(outputFileSize - 8);
	Output.Pos := outputFileSize;
end;
//====================================================================================================//
//                                                Load                                                //
//====================================================================================================//
function TFsbReaderClass.LoadFsbSamples():Boolean;
begin
	Result := false;
	if not (fFsbFile.IsOpen) then
		Exit;
	ReadHeaderToken();
	case fMajorVersion of
	3,4: Result := LoadFsb3And4();
	5: Result := LoadFsb5();
	end;
end;
//----------------------------------------------------------------------------------------------------//
function TFsbReaderClass.LoadFsb3And4():Boolean;
var
	header: FSOUND_FSB_HEADER_3;
	hdrSample: FSOUND_FSB_SAMPLE_HEADER_3_1;
	hdrBasicSample: FSOUND_FSB_SAMPLE_HEADER_BASIC;
	i, hdrSize, seeker, offset, firstIndex: Integer;
	totalSize: LongWord;
	sample: PFsbSampleEntry;
	aligned: Boolean;
begin
	Result := false;
	{ header }
	fFsbFile.Read(SizeOf(FSOUND_FSB_HEADER_3),@header);
	if (header.entries < 0) or (header.entries > $FFFF) or (header.hdrSizeTotal < 0) or (header.hdrSizeTotal > $FFFFFF) or (header.dataSizeTotal < 0) then begin
		if (@fOnLogEvent <> nil) then
			fOnLogEvent(Self,Format('Invalid %s parameters (%d, %d, %d)',[AnsiString(header.fileID),header.entries,header.hdrSizeTotal,header.dataSizeTotal]),1,clRed,LOG_BOLD or LOG_MSGBOX_WARN);
		Exit;
	end;
	fHeader.FileID := header.fileID;
	fHeader.version := header.version;
	fHeader.flags := header.flags;
	fHeader.headerSize := header.hdrSizeTotal;
	fHeader.dataSize := header.dataSizeTotal;
	{ Log }
	if (@fOnLogEvent <> nil) then begin
		fOnLogEvent(Self,Format('FileID is <%s>  |  Version is %d.%d  |  Number of Entries %d',[string(header.fileID),HiWord(header.version),LoWord(header.version),header.entries]),1,clNavy,0);
		if (header.flags > 0) then begin
			fOnLogEvent(Self,Format('Global Flags [%s%.8x]',[HexDisplayPrefix,header.flags]),1,clBlack,LOG_BOLD);
			for i := 0 to High(FSB_HEADER_FLAGS) do begin
				if (header.flags and FSB_HEADER_FLAGS[i].flag <> 0) then
					fOnLogEvent(Self,Format('%s%.2x  |  %s  |  %s',[HexDisplayPrefix,FSB_HEADER_FLAGS[i].flag,FSB_HEADER_FLAGS[i].name,FSB_HEADER_FLAGS[i].info]),2,clNavy,0);
			end;
		end;
	end;
	{ Determine Header Size }
	if (header.fileID = 'FSB3') then
		hdrSize := SizeOf(FSOUND_FSB_HEADER_3)
	else if (header.fileID = 'FSB4') then
		hdrSize := SizeOf(FSOUND_FSB_HEADER_4)
	else
		hdrSize := 0;
	{ Check integrity -- never seen any mismatches yet though }
	if (fFileOffset = 0) then begin
		totalSize := (hdrSize + header.hdrSizeTotal + header.dataSizeTotal);
		if (@fOnLogEvent <> nil) and (totalSize <> fFileSize) then begin
			fOnLogEvent(Self,'Combined section size did not match total filesize. File data has most likely been corrupt or truncated.',1,clRed,LOG_BOLD or LOG_MSGBOX_WARN);
			fOnLogEvent(Self,Format('Filesize = %.0n bytes  |  Combined Size = %.0n bytes  |  Difference = %.0n bytes',[fFileSize / 1,totalSize / 1,fFileSize / 1 - totalSize / 1]),2,clMaroon,0);
		end;
	end;
	{ Aligned FSB }
	aligned := (header.flags and FMOD_FSB_SOURCE_MPEG_PADDED4 > 0);
	{ Abort if FSB contain no samples }
	if (header.entries = 0) then begin
		if (@fOnLogEvent <> nil) then
			fOnLogEvent(Self,'File does not contain any samples.',1,clRed,LOG_BOLD or LOG_MSGBOX_WARN);
		Result := true;
		Exit;
	end;
	{ read sample data }
	firstIndex := High(fSamples) + 1;
	SetLength(fSamples,Length(fSamples) + header.entries);
	FillChar(fSamples[firstIndex],SizeOf(TFsbSampleEntry) * header.entries,0);
	seeker := fFileOffset + hdrSize;
	offset := (fFileOffset + hdrSize + header.hdrSizeTotal);
	for i := 0 to header.entries - 1 do begin
		fFsbFile.Pos := seeker;
		sample := @fSamples[firstIndex + i];
		sample^.hdrOffset := seeker;
		sample^.dataOffset := offset;
		{ read sample header & fill internal entry -- basic headers use same parameters as the first sample }
		if (header.flags and FMOD_FSB_SOURCE_BASICHEADERS = 0) or (i = 0) then begin
			fFsbFile.Read(SizeOf(FSOUND_FSB_SAMPLE_HEADER_3_1),@hdrSample);
			StrLCopy(sample^.samplename,hdrSample.filename,SizeOf(hdrSample.filename));
			sample^.hdrSize := hdrSample.entrySize;
			sample^.dataSize := hdrSample.size;
			sample^.samples := hdrSample.samples;
		end
		else begin
			fFsbFile.Read(SizeOf(FSOUND_FSB_SAMPLE_HEADER_BASIC),@hdrBasicSample);
			StrCopy(sample^.samplename,PChar(Format('%d',[StrToIntDef(hdrSample.filename,0) + i])));	// name the sample based of the first sample's number
			sample^.hdrSize := SizeOf(FSOUND_FSB_SAMPLE_HEADER_BASIC);
			sample^.dataSize := hdrBasicSample.lengthCompressedBytes;
			sample^.samples := hdrBasicSample.lengthSamples;
		end;
		sample^.flags := hdrSample.mode;
		sample^.channels := hdrSample.channels;
		sample^.freq := hdrSample.freq;
		sample^.loopStart := hdrSample.loopStart;
		sample^.loopEnd := hdrSample.loopEnd;

		sample^.defVol := hdrSample.defVol;
		sample^.defPan := hdrSample.defPan;
		sample^.defPri := hdrSample.defPri;
		sample^.minDistance := hdrSample.minDistance;
		sample^.maxDistance := hdrSample.maxDistance;
		sample^.varFreq := hdrSample.varFreq;
		sample^.varVol := hdrSample.varVol;
		sample^.varPan := hdrSample.varPan;
		{ precalc misc }
		if (sample^.channels <> 0) and (sample^.samples <> 0) then
			sample^.bitsPerSample := (sample^.dataSize / sample^.channels / sample^.samples * 8);
		{ set sample format -- default to PCM }
		if (sample^.flags and FSOUND_IMAADPCM <> 0) or (sample^.flags and FSOUND_GCADPCM <> 0) then
			sample^.format := FSB5_SAMPLE_FORMAT_ADPCM
		else if (sample^.flags and FSOUND_XMA <> 0) then
			sample^.format := FSB5_SAMPLE_FORMAT_XMA
		else if (sample^.flags and FSOUND_MPEG <> 0) or (sample^.flags and FSOUND_MPEG_LAYER3 <> 0) or (sample^.flags and FSOUND_MPEG_LAYER2 <> 0) then
			sample^.format := FSB5_SAMPLE_FORMAT_MPEG
		else if (sample^.flags and FSOUND_OGG <> 0) or (sample^.flags and FSOUND_CELT <> 0) then
			sample^.format := FSB5_SAMPLE_FORMAT_VORBIS
		else
			sample^.format := FSB5_SAMPLE_FORMAT_PCM16;
		{ next }
		Inc(seeker,sample^.hdrSize);
		Inc(offset,sample^.dataSize);
		if (aligned) and (offset and 31 <> 0) then		// aligned on 32 byte border
			offset := (offset + 31) and (not 31);
	end;
	{ return true }
	Result := true;
end;
//----------------------------------------------------------------------------------------------------//
function TFsbReaderClass.LoadFsb5():Boolean;
const
	DEFAULT_CHANNELS	= 1;
	DEFAULT_FREQ		= 44100;
var
	header: FSB_HEADER_5;
	fsbHdrSize, offset, baseDataOffset, totalSize: LongWord;
	buf: PChar;
	i, a, b, extraSize, firstIndex: Integer;
	extraNext, extraType: Byte;
	sample, sampleNext: PFsbSampleEntry;
begin
	Result := false;
	{ header }
	fFsbFile.Read(SizeOf(FSB_HEADER_5),@header);
	if (header.entries > $FFFF) or (header.infoSizeTotal > $FFFFFF) or (header.nameSizeTotal > $FFFFFF) or (header.formatId > $FF) then begin
		if (@fOnLogEvent <> nil) then
			fOnLogEvent(Self,Format('Invalid %s parameters (%u, %u, %u, %u).',[AnsiString(header.fileID),header.entries,header.infoSizeTotal,header.nameSizeTotal,header.formatId]),1,clRed,LOG_BOLD or LOG_MSGBOX_WARN);
		Exit;
	end;
	fHeader.FileID := header.fileID;
	fHeader.version := header.version;
	fHeader.flags := 0;
	fHeader.headerSize := header.infoSizeTotal;
	fHeader.dataSize := header.dataSizeTotal;
	{ Log }
	if (@fOnLogEvent <> nil) then begin
		fOnLogEvent(Self,Format('FileID is <%s>  |  Version is %d.%d  |  Number of Entries %d',[string(header.fileID),HiWord(header.version),LoWord(header.version),header.entries]),1,clNavy,0);
		fOnLogEvent(Self,Format('Samples are stored in %s format (%s%.2x)',[GetSampleFormatName(header.formatId),HexDisplayPrefix,header.formatId]),1,clNavy,0);
		if (fLogVerbose) then begin
			fOnLogEvent(Self,'FSB5 Structure Data, 32 bytes (unknown)',1,clBlack,LOG_BOLD);
			fOnLogEvent(Self,Format('zero[0]  = %s%.8x',[HexDisplayPrefix,PLongWord(@header.zero[0])^]),2,clMaroon,0);
			fOnLogEvent(Self,Format('zero[1]  = %s%.8x',[HexDisplayPrefix,PLongWord(@header.zero[4])^]),2,clMaroon,0);
			fOnLogEvent(Self,Format('hash[0]  = %s%.8x',[HexDisplayPrefix,PLongWord(@header.hash[0])^]),2,clMaroon,0);
			fOnLogEvent(Self,Format('hash[1]  = %s%.8x',[HexDisplayPrefix,PLongWord(@header.hash[4])^]),2,clMaroon,0);
			fOnLogEvent(Self,Format('hash[2]  = %s%.8x',[HexDisplayPrefix,PLongWord(@header.hash[8])^]),2,clMaroon,0);
			fOnLogEvent(Self,Format('hash[3]  = %s%.8x',[HexDisplayPrefix,PLongWord(@header.hash[12])^]),2,clMaroon,0);
			fOnLogEvent(Self,Format('dummy[0] = %s%.8x',[HexDisplayPrefix,PLongWord(@header.dummy[0])^]),2,clMaroon,0);
			fOnLogEvent(Self,Format('dummy[1] = %s%.8x',[HexDisplayPrefix,PLongWord(@header.dummy[4])^]),2,clMaroon,0);
		end;
	end;
	{ Total Header Size is 64 for version 0, but only 60 for version 1. No idea why that is }
	fsbHdrSize := SizeOf(FSB_HEADER_5);
	if (header.version = 0) then
		Inc(fsbHdrSize,4);
	{ Check integrity -- never seen any mismatches yet though }
	if (@fOnLogEvent <> nil) and (fFileOffset = 0) then begin
		totalSize := (fsbHdrSize + header.infoSizeTotal + header.nameSizeTotal + header.dataSizeTotal);
		if (totalSize <> fFileSize) then begin
			fOnLogEvent(Self,'Combined section size did not match total filesize. File data has most likely been corrupt or truncated.',1,clRed,LOG_BOLD or LOG_MSGBOX_WARN);
			fOnLogEvent(Self,Format('Filesize = %.0n bytes  |  Combined Size = %.0n bytes  |  Difference = %.0n bytes',[fFileSize / 1,totalSize / 1,(fFileSize - totalSize) / 1]),2,clMaroon,0);
		end;
	end;
	{ Abort if FSB contain no samples }
	if (header.entries = 0) then begin
		if (@fOnLogEvent <> nil) then
			fOnLogEvent(Self,'File does not contain any samples.',1,clRed,LOG_BOLD or LOG_MSGBOX_WARN);
		Result := true;
		Exit;
	end;
	{ Init Entries }
	firstIndex := High(fSamples) + 1;
	SetLength(fSamples,Length(fSamples) + Integer(header.entries));
	FillChar(fSamples[firstIndex],SizeOf(TFsbSampleEntry) * header.entries,0);
	{ Read Names -- If FSB has no filetable, just set the samplenames with their integer index }
	if (header.nameSizeTotal > 0) then begin
		offset := (LongWord(fFileOffset) + fsbHdrSize + header.infoSizeTotal);
		fFsbFile.Pos := offset;
		GetMem(buf,header.nameSizeTotal);
		fFsbFile.Read(header.nameSizeTotal,buf);
		for i := 0 to header.entries - 1 do begin
			offset := PInteger(@buf[i * 4])^;
			sample := @fSamples[firstIndex + i];
			StrLCopy(@sample^.samplename,PChar(@buf[offset]),SizeOf(sample^.samplename));
			{ check sample name buffer size -- Az: never seen this trigger }
			if (fLogVerbose) and (@fOnLogEvent <> nil) and (StrLen(@buf[offset]) > SizeOf(sample^.samplename)) then
				fOnLogEvent(Self,Format('The sample name length (%d) was too large for the buffer (%d) to hold sample[%.2d]: "%s"',[StrLen(@buf[offset]),SizeOf(sample^.samplename),i,PChar(@buf[offset])]),1,clRed,0);
		end;
		FreeMem(buf,header.nameSizeTotal);
	end
	else begin
		for i := 0 to header.entries - 1 do begin
			sample := @fSamples[firstIndex + i];
			StrLCopy(@sample^.samplename,PChar(Format('%d',[firstIndex + i])),SizeOf(sample^.samplename));
		end;
	end;
	{ Read Sample Info }
	baseDataOffset := (LongWord(fFileOffset) + fsbHdrSize + header.infoSizeTotal + header.nameSizeTotal);
	offset := LongWord(fFileOffset) + fsbHdrSize;
	fFsbFile.Pos := offset;
	if (fLogVerbose) and (@fOnLogEvent <> nil) then
		fOnLogEvent(Self,'Verbose Sample Details',1,clBlack,LOG_BOLD);
	for i := 0 to header.entries - 1 do begin
		sample := @fSamples[firstIndex + i];
		sample^.format := header.formatId;
		sample^.hdrOffset := fFsbFile.Pos;
		if (fLogVerbose) and (@fOnLogEvent <> nil) then
			fOnLogEvent(Self,Format('Sample[%.2d]:  "%s"',[i,sample^.samplename]),2,clBlack,LOG_BOLD);
		{ reset loop values }
		sample^.loopStart := -1;
		sample^.loopEnd := -1;
		{ read }
		a := fFsbFile.ReadInt32();	// 26 msb = dataOffset / 0x10 | 6 lsb = mode flags -- Az: 14.02.08: seems like it might be the 6 or 7 lsb, not 8?
		b := fFsbFile.ReadInt32();	// 30 msb = samples           | 2 lsb = unknown
		if (b and 3 > 0) and (@fOnLogEvent <> nil) then begin
			fOnLogEvent(Self,Format('The 2 least significant bits were not zero.  |  Binary bit value = 0b%s  |  Hex = %s%x',[AzIntToBin(b and 3,2),HexDisplayPrefix,b]),3,clRed,0);
		end;
		{ defaults }
		sample^.channels := DEFAULT_CHANNELS;
		sample^.freq := DEFAULT_FREQ;
		{ set sample info }
		sample^.samples := (b shr 2);
		sample^.flags := (a and (1 shl 6 - 1));	// 14.02.08: changed from 8 to 6 lsb -- Code Was: (a and $FF);
		sample^.dataOffset := baseDataOffset + LongWord(a shr 2 and not $F);		// ignores the 6 lower bits (2 + 4) -- same as shr 6 shl 4
		if (sample^.flags and FSB5_SAMPLE_STEREO > 0) then
			sample^.channels := 2;
		{ extra -- 7 msb = type | 24 bits = size | 1 lsb = hasExtraData }
		{ 2014.02.08: changed | size = 23 -> 24 bits | type = 8 -> 7 bits }
		extraNext := (a and 1);
		while (extraNext <> 0) do begin
			a := fFsbFile.ReadInt32();
			extraNext := (a and 1);
			extraSize := (a shr 1 and (1 shl 24 - 1));
			extraType := (a shr 25);
			case extraType of
			FSB5_EXTRA_CHANNEL:
				begin
					sample^.channels := fFsbFile.ReadInt8();
					if (fLogVerbose) and (@fOnLogEvent <> nil) then
						fOnLogEvent(Self,Format('EXTRA: raw = 0x%x, next = %d, type = %d, offset = %d, size = %d  ->  chn = %d',[a,extraNext,extraType,fFsbFile.Pos,extraSize,sample^.channels]),3,clGreen,0);
				end;
			FSB5_EXTRA_FREQ:
				begin
					sample^.freq := fFsbFile.ReadInt32();
					if (fLogVerbose) and (@fOnLogEvent <> nil) then
						fOnLogEvent(Self,Format('EXTRA: raw = 0x%x, next = %d, type = %d, offset = %d, size = %d  ->  freq = %d Hz',[a,extraNext,extraType,fFsbFile.Pos,extraSize,sample^.freq]),3,clGreen,0);
				end;
			FSB5_EXTRA_LOOP:
				begin
					sample^.loopStart := fFsbFile.ReadInt32();
					sample^.loopEnd := fFsbFile.ReadInt32();
					if (fLogVerbose) and (@fOnLogEvent <> nil) then
						fOnLogEvent(Self,Format('EXTRA: raw = 0x%x, next = %d, type = %d, offset = %d, size = %d  ->  loop = %d / %d',[a,extraNext,extraType,fFsbFile.Pos,extraSize,sample^.loopStart,sample^.loopEnd]),3,clGreen,0);
				end;
			else
				{ unknown extra types }
				if (fLogVerbose) and (@fOnLogEvent <> nil) then
					fOnLogEvent(Self,Format('EXTRA: raw = 0x%x, next = %d, type = %d, offset = %d, size = %d  |  unknown extra type (%2:d)',[a,extraNext,extraType,fFsbFile.Pos,extraSize]),3,clPurple,0);
				fFsbFile.Pos := fFsbFile.Pos + extraSize;
(*				SetLength(extraStore,extraSize);
				AzFileRead(fsbFile,extraSize,@extraStore[0]);
				AzFileWriteBlock(dumpFolder + entries[i].samplename + '.' + IntToStr(extraType),0,extraSize,@extraStore[0],true);//*)
			end;
		end;
		sample^.hdrSize := (LongWord(fFsbFile.Pos) - sample^.hdrOffset);
	end;
	{ Calculate Data Size and BitsPerSample }
	if (header.entries <> 0) then
		fSamples[High(fSamples)].dataSize := (baseDataOffset + header.dataSizeTotal - fSamples[High(fSamples)].dataOffset);
	for i := 0 to High(fSamples) do begin
		sample := @fSamples[firstIndex + i];
		sampleNext := @fSamples[firstIndex + i + 1];
		if (i < High(fSamples)) and (sample^.dataOffset < sampleNext^.dataOffset) and (sampleNext^.dataOffset <= fFileSize) then
			sample^.dataSize := (sampleNext^.dataOffset - sample^.dataOffset);
		if (sample^.channels <> 0) and (sample^.samples <> 0) then
			sample^.bitsPerSample := (sample^.dataSize / sample^.channels / sample^.samples * 8);
	end;
	{ return true }
	Result := true;
end;
//----------------------------------------------------------------------------------------------------//

end.
