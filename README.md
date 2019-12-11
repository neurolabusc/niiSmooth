## About

Neuroimaging data is ofter blurred with a Gaussian smoothing kernel. This step can remove noise spikes, improve signal-to-noise, reduce [effective number of statistical comparisons](https://www.fil.ion.ucl.ac.uk/spm/doc/books/hbf2/pdfs/Ch14.pdf) and helps ensure data roughly matches the assumptions of the general linear model statistics. While niave implementations of the Gaussian blur are slow, it is a [separable filter](https://en.wikipedia.org/wiki/Gaussian_blur), so we can process each dimension sequentially. Within each dimension, we can process all the lines in parallel. This simple project provides a high performance implementation and compares favorably to other tools. 

This tool use the CPU, and therefore does not require a graphics card that supports GLSL or CUDA. It should be noted that [graphics cards](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/OpenCL_MacProgGuide/TuningPerformanceOntheGPU/TuningPerformanceOntheGPU.html#//apple_ref/doc/uid/TP40008312-CH22-SW4) have a huge number of cores and hardware-based sampling that can [aid Gaussian blurs](https://gamedev.stackexchange.com/questions/26649/glsl-one-pass-gaussian-blur/26655). On the other hand, graphics cards have slow memory latency, these operations are probably memory bound for typical neuroimaging datasets.

This software can read any of the medical formats supported by [i2nii](https://github.com/rordenlab/i2nii), but it only writes NIfTI format images.

## Installation

You can get Depth3D using two methods:

 - (Recommended) Download latest compiled release from [Github release web page](https://github.com/neurolabusc/niiSmooth/releases).
 - (Recommended) You can also download from the command line for Linux, MacOS and Windows:
   * `curl -fLO https://github.com/neurolabusc/niiSmooth/releases/latest/download/niiSmooth_lnx.zip`
   * `curl -fLO https://github.com/neurolabusc/niiSmooth/releases/latest/download/niiSmooth_mac.zip`
   * `curl -fLO https://github.com/neurolabusc/niiSmooth/releases/latest/download/niiSmooth_win.zip`
 - (Developers) Download the source code from [GitHub](https://github.com/neurolabusc/niiSmooth).

## Usage

```
Chris Rorden's niiSmooth v1.0.20191206
usage: niiSmooth [options] <in_file(s)>
Reads volume and computes distance fields
OPTIONS
 -3 : save 4D data as 3D files (y/n, default n)
 -f : full-width half maximum in mm (default 8)
 -d : output datatype (in/u8/u16/f32 default in)
 -h : show help
 -m : mask name (optional, only weight voxels in mask)
 -o : output name (omit to save as input name with "depth_" prefix)
 -p : parallel threads (0=optimal, 1=one, 5=five, default 0)
 -z : gz compress images (y/n, default n)
 Examples :
  niiSmooth -f 8 fmri.nii
  niiSmooth -f 4 -m T1mask.nii T1.nii
```

## Performance

Here is the time to convert a 345mb resting state dataset (90x90x50x427 16-bit) with a 6mm FWHM on a 12-core (24-thread) Ryzen 3900X computer.

| Tool | Time (.nii) | Time (.nii.gz) |
| --- | --- | --- |
| AFNI<sup>1</sup> | 1.5 | 24.3 | 
| niiSmooth<sup>2</sup> | 2.3 | 3.6<sup>3</sup> | 
| c4d | 16.7 | 40.0 |
| FSL | 20.0 | 44.3 |
| SPM12 | 22.2 | - |

1. By default, AFNI uses a smaller, faster, and less precise kernel width (AFNI_BLUR_FIRFAC) than other methods. AFNI uses parallel pigz for compressing for BRIK.GZ (3.1s) but not .nii.gz (24.3s).
2. niiSmooth requires 7.3s to create uncompressed .nii in single-threaded mode
3. niiSmooth (and AFNI when creating BRIK.GZ) can use pigz to accelerate compression. These times are with the default version of pigz, and compression will be accelerated a futuer 40% if the user installs an [optimized version of pigz](https://github.com/neurolabusc/pigz/releases/tag/v2.4.cf). 

```
//High performance smoothing
//Note some tools use FWHM others use Sigma, 6mm FWHM = 2.548mm Sigma 
//Set ~/.afnirc for AFNI_COMPRESSOR = pigz
niiSmooth -f 6 -d f32 ~/Neuro/rest.nii
time niiSmooth -f 6 -d f32 -z y ~/Neuro/rest.nii
time niiSmooth -f 6 -d f32  -p 1 ~/Neuro/rest.nii
time fslmaths rest.nii -s 2.548 fsl 
FSLOUTPUTTYPE=NIFTI; time fslmaths rest.nii -s 2.5480 fsl
time c4d ~/Neuro/rest.nii -smooth 2.548mm -o c3d.nii
time c4d ~/Neuro/rest.nii -smooth 2.548mm -o c3d.niigz
time 3dmerge -1blur_fwhm 6.0 -doall -prefix afni.nii rest.nii
time 3dmerge -1blur_fwhm 6.0 -doall -prefix afni.nii.gz rest.nii
time 3dmerge -1blur_fwhm 6.0 -doall -prefix afni.brik.gz rest.nii
//next command from Matlab
tic; spm_smooth('rest.nii','spm.nii',6); toc
```

## Compiling

Most people will want to download a [pre-compiled executable](https://github.com/neurolabusc/niiSmooth/releases). However, it is easy to compile.

 - Download and install [FreePascal for your operating system](https://www.freepascal.org/download.html). For Debian-based unix this may be as easy as `sudo apt-get install fp-compiler`. For other operating systems, you may simply want to install FreePascal from the latest [Lazarus distribution](https://sourceforge.net/projects/lazarus/files/).
 - From the terminal, go inside the directory with the source files and run the following commands to compile the program:

```
 fpc -CX -Xs -XX -O3 niiSmooth
```


