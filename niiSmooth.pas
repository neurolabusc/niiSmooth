program niiSmooth;
//Compute each voxels distance from edge of cluster
//   fpc -CX -Xs -XX -O3 niiSmooth

{$mode Delphi} //{$mode objfpc}
{$H+}
uses 
	{$ifdef unix}
	cthreads, cmem, // the c memory manager is on some systems much faster for multi-threading
	{$endif}
	SimdUtils, VectorMath,
	dateutils, StrUtils, sysutils, Classes, nifti_types, 
	nifti_loadsave, nifti_smooth, math;

const
    kEXIT_SUCCESS = 0;
    kEXIT_FAIL = 1;
    kEXIT_PARTIALSUCCESS = 2; //processed some but not all input files
    kVers = 'v1.0.20191206';

//High performance smoothing
//Note some tools use FWHM others use Sigma
//  divide FWHM (in mm) by 2.3548 to get sigma, so 6mm FWHM = 3.39731612 Sigma
//  test 90x90x50x427 16-bit 345mb 6mm FWHM
// niiSmooth 2.32 time ./niiSmooth -f 6 -d f32 ~/Neuro/rest.nii
// niiSmooth 3.63 time ./niiSmooth -f 6 -d f32 -z y ~/Neuro/rest.nii
// niiSmooth 7.30 time ./niiSmooth -f 6 -d f32  -p 1 ~/Neuro/rest.nii
// spm 22.2 tic; spm_smooth('rest.nii','spm.nii',6); toc
// FSL 44.3 time fslmaths rest.nii -s 2.5480 fsl 
// FSL 20 FSLOUTPUTTYPE=NIFTI; time fslmaths rest.nii -s 2.5480 fsl
// c4d 16.7 time ./c4d ~/Neuro/rest.nii -smooth 2.5480mm -o c3d.nii
// c4d 40.0 time ./c4d ~/Neuro/rest.nii -smooth 2.5480mm -o c3d.niigz
// afni 1.478 time 3dmerge -1blur_fwhm 6.0 -doall -prefix afni.nii rest.nii
// set AFNI_COMPRESSOR to pigz
// afni 24.347 time 3dmerge -1blur_fwhm 6.0 -doall -prefix afni.nii.gz rest.nii
// afni 3.143 time 3dmerge -1blur_fwhm 6.0 -doall -prefix afni.brik.gz rest.nii

function smoothAll(fnm, outName: string; isGz, is3D: boolean; FWHMmm: single = 8; outDataType: integer = kDT_input; maskName: string = ''; maxthreads: integer = 0): boolean;
var
	hdr, hdrIn: TNIFTIhdr;
	img: TUInt8s;
	isInputNIfTI: boolean;
	ext: string;
begin
	result := false;
	if not loadVolumes(fnm, hdr, img, isInputNIfTI) then exit;
	if outName = '' then 
		outName := extractfilepath(fnm)+'s'+extractfilename(changefileext(fnm,''))
	else
		outName := changefileext(outName,'');
	//handle double extensions: img.nii.gz and img.BRIK.gz
	ext := upcase(extractfileext(outName));
	if (ext = '.NII') or (ext = '.BRIK') then
		outName := changefileext(outName,'');
	hdr.intent_code := kNIFTI_INTENT_NONE; //just in case input is labelled map
	hdrIn := hdr;
	changeDataType(hdr, img, kDT_FLOAT32);
	if (maskName <> '') then begin
		if not applyMask(maskName, hdr, TFloat32s(img), NaN) then
			exit;
		nii_smooth_gauss(hdr, TFloat32s(img), FWHMmm, maxthreads, true);	
	end else
		nii_smooth_gauss(hdr, TFloat32s(img), FWHMmm, maxthreads);
	changeDataType(hdrIn, hdr, img, outDataType);	
	result := saveNii(outName, hdr, img, isGz, is3D, maxthreads);
end;

procedure showhelp;
var
    exeName: string;
begin
    exeName := extractfilename(ParamStr(0));
    {$IFDEF WINDOWS}
    exeName := ChangeFileExt(exeName, ''); //i2nii.exe -> i2nii
    os := 'Windows';
    {$ENDIF}
    writeln('Chris Rorden''s '+exeName+' '+kVers);
    writeln(format('usage: %s [options] <in_file(s)>', [exeName]));
	writeln('Reads volume and computes distance fields');
	writeln('OPTIONS');
    writeln(' -3 : save 4D data as 3D files (y/n, default n)');
    writeln(' -f : full-width half maximum in mm (default 8)');
    writeln(' -d : output datatype (in/u8/u16/f32 default in)');
    writeln(' -h : show help');
    writeln(' -m : mask name (optional, only weight voxels in mask)');
    writeln(' -o : output name (omit to save as input name with "depth_" prefix)');
    writeln(' -p : parallel threads (0=optimal, 1=one, 5=five, default 0)');
    writeln(' -z : gz compress images (y/n, default n)');
    writeln(' Examples :');
    writeln(format('  %s -f 8 fmri.nii', [exeName]));
    writeln(format('  %s -f 4 -m T1mask.nii T1.nii', [exeName]));
end;

function doRun: integer;
var
	i, nOK, nAttempt: integer;
	is3D: boolean = false;
    isGz: boolean = false;
    isShowHelp: boolean = false;
    startTime: TDateTime;
    outDataType: integer = kDT_input;
    FWHMmm: single = 8;
    maxthreads: integer = 0;
    outName: string = '';
    maskName: string = '';
    s, v: string;
    c: char;
begin
	startTime := Now;
	result := kEXIT_SUCCESS;
	nOK := 0;
	nAttempt := 0;
	i := 1;
	while i <= ParamCount do begin
        s := ParamStr(i);
        i := i + 1;
        if length(s) < 1 then continue; //possible?
        if s[1] <> '-' then begin
            nAttempt := nAttempt + 1;
            if smoothAll(s, outName, isGz, is3D, FWHMmm, outDataType, maskName, maxthreads) then
                nOK := nOK + 1;
            continue;
        end;
        if length(s) < 2 then continue; //e.g. 'i2nii -'
        c := upcase(s[2]);
		if c = 'H' then showhelp;
		if i = ParamCount then continue;
        v := ParamStr(i);
        i := i + 1;
        if length(v) < 1 then continue; //e.g. 'i2nii -o ""'
        if c =  '3' then
            is3D := upcase(v[1]) = 'Y'; 
        if c = 'D' then begin
       		v := upcase(v);
       		//if Pos('I8',v) > 0 then outDataType := kDT_INT8;
       		//if Pos('I16',v) > 0 then outDataType := kDT_INT16;
       		if Pos('U8',v) > 0 then outDataType := kDT_UINT8;
       		if Pos('U16',v) > 0 then outDataType := kDT_UINT16;
       		if Pos('F32',v) > 0 then outDataType := kDT_FLOAT32;
       		if Pos('IN',v) > 0 then outDataType := kDT_input;
        end;
        if c =  'F' then
            FWHMmm := strtofloatdef(v, FWHMmm); 
        if c =  'M' then   
            maskName := v;
        if c =  'O' then
            outName := v;
        if c =  'P' then
            maxthreads := strtointdef(v, 0); 
        if c =  'Z' then
            isGz := upcase(v[1]) = 'Y';			
	end;
    if (ParamCount = 0) or (isShowHelp) then
        ShowHelp;
    if nOK > 0 then 
        writeln(format('Smoothing with FWHM = %gmm (Sigma=%g) required %.3f seconds.', [FWHMmm, FWHMmm/2.3548, MilliSecondsBetween(Now,startTime)/1000.0]));
    if (nOK = nAttempt) then
        ExitCode := kEXIT_SUCCESS
    else if (nOK = 0) then
        ExitCode := kEXIT_FAIL
    else
        ExitCode := kEXIT_PARTIALSUCCESS;
end;

begin
    ExitCode := doRun;
end.