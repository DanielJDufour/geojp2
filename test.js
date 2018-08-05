var fs = require('fs');

var Module = require('./gdal.js');
console.log('gdal:', Module);

// initialize gdal
Module.ccall('GDALAllRegister', null, [], []);

// set up js proxy function
var GDALOpen = Module.cwrap('GDALOpen', 'number', ['string']);

var GDALGetRasterXSize = Module.cwrap('GDALGetRasterXSize', 'number', ['number']);


var buffer = fs.readFileSync('./test.tiff');

var fakename = 'raster.tiff';

var created = Module.FS_createDataFile('/', fakename, buffer, true, true);
//var created = Module.writeFile(fakename, buffer, { encoding: 'binary' });
console.log("created:", typeof created);

console.log("abotu to run GDALOpen", GDALOpen);
var dataset = GDALOpen(fakename);
console.log("opened:", dataset);

var xsize = GDALGetRasterXSize(dataset);
console.log("xsize:", xsize);






var buffer = fs.readFileSync('./B01.jp2');

var fakename = 'raster.jp2';

var created = Module.FS_createDataFile('/', fakename, buffer, true, true);
//var created = Module.writeFile(fakename, buffer, { encoding: 'binary' });
console.log("created:", typeof created);

console.log("abotu to run GDALOpen", GDALOpen);
var dataset = GDALOpen(fakename);
console.log("opened:", dataset);

var xsize = GDALGetRasterXSize(dataset);
console.log("xsize:", xsize);

