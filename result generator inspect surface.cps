/**
  Copyright (C) 2012-2020 by Autodesk, Inc.
  All rights reserved.

  Result file generator inspect surface

  $Revision$
  $Date$
  
  FORKID {FF934B58-50E7-0763-431D-17ECD207B2CD}
*/

description = "Result file generator inspect surface";
vendor = "Autodesk";
vendorUrl = "http://www.autodesk.com";
legal = "Copyright (C) 2012-2020 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 40783;

longDescription = "This postprocessor generates a measurement results file in standard MTIL format.";

extension = "MSR";
if (getCodePage() == 932) { // shift-jis is not supported
  setCodePage("ascii");
} else {
  setCodePage("ansi"); // setCodePage("utf-8");
}

capabilities = CAPABILITY_MILLING;
tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.25, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(90);

properties = {
  upperDeviationAllowance: 0,
  lowerDeviationAllowance: 0,
  // radialSizeOffset: 0,
  deviationAllowanceType: "NONE",
  rotationVector: "Z"
};

propertyDefinitions = {
  deviationAllowanceType: {
    title:"Deviation Allowance Type",
    description:"Specifies the deviation allowance type to apply to the results file",
    type:"enum",
    values:[
      {title:"POINT Z VECTOR", id:"POINT Z VECTOR"},
      {title:"NONE", id:"NONE"},
      {title:"OFFSETX", id:"OFFSETX"},
      {title:"OFFSETXY", id:"OFFSETXY"},
      {title:"OFFSETXZ", id:"OFFSETXZ"},
      {title:"OFFSETY", id:"OFFSETY"},
      {title:"OFFSETYZ", id:"OFFSETYZ"},
      {title:"OFFSETZ", id:"OFFSETZ"},
      {title:"RANDOM", id:"RANDOM"},
      {title:"ROTARY", id:"ROTARY"}
    ]
  },
  upperDeviationAllowance: {title:"Upper deviation allowance", description:"Specifies the upper deviation allowance.", type:"number", group:0},
  lowerDeviationAllowance: {title:"Lower deviation allowance", description:"Specifies the lower deviation allowance.", type:"number", group:0},
  // radialSizeOffset: {title:"Radial Size Offset", description:"Enter a probe radial size offset to apply", type:"number", group:1},
  rotationVector: {
    title:"Rotary Vector",
    description:"Enter the axis letter to which the rotation is applied to.",
    type:"enum",
    values:[
      {title:"X", id:"X"},
      {title:"Y", id:"Y"},
      {title:"Z", id:"Z"}
    ]
  }
};

// fixed settings
var maximumLineLength = 80; // the maximum number of charaters allowed in a line

// collected state
var pointNumber = 1;
var xyzFormat = createFormat({decimals:(unit == MM ? 4 : 5), forceSign:true});
var abcFormat = createFormat({decimals:(unit == MM ? 4 : 5), forceSign:true, scale:DEG});
var ijkFormat = createFormat({decimals:(unit == MM ? 6 : 8), forceDecimal:true});
var commentStart = ";";
var commentEnd = "";
var nominalXYZrot = new Vector();
var normalizedVector = new Vector();
var measuredXYZ = new Vector();
// var realRadius = 0;

function writeBlock() {
  var text = formatWords(arguments);
  if (!text) {
    return;
  }
  writeWords(arguments);
}

function formatComment(text) {
  return commentStart + String(text).replace(/[()]/g, "") + commentEnd;
}

function writeComment(text) {
  writeln(formatComment(text.substr(0, maximumLineLength - 2)));
}

function inspectionCreateResultsFileHeader() {
  if (pointNumber == 1) {
    writeln("START");
    if (hasGlobalParameter("document-id")) {
      writeln("DOCUMENTID " + getGlobalParameter("document-id"));
    }
    if (hasGlobalParameter("model-version")) {
      writeln("MODELVERSION " + getGlobalParameter("model-version"));
    }
  }
}

function inspectionCalculateVectors() {
  var nominalXYZ = new Vector(cycle.nominalX, cycle.nominalY, cycle.nominalZ);
  var nominalIJK = new Vector(cycle.nominalI, cycle.nominalJ, cycle.nominalK);

  var m = getRotation();

  nominalXYZrot = m.multiply(nominalXYZ);
  normalizedVector = m.multiply(nominalIJK).normalized;
}

function inspectionRadiusOffset() {
  // realRadius = tool.cornerRadius + properties.radialSizeOffset;
  var radiusOffset = Vector.product(normalizedVector, tool.cornerRadius);
  measuredXYZ = Vector.sum(nominalXYZrot, radiusOffset);
}

function inspectionCalculateNominals() {
  cycle.nominalX = nominalXYZrot.x;
  cycle.nominalY = nominalXYZrot.y;
  cycle.nominalZ = nominalXYZrot.z;
  cycle.nominalI = normalizedVector.x;
  cycle.nominalJ = normalizedVector.y;
  cycle.nominalK = normalizedVector.z;
}

function inspectionCalculateMeasured() {
  cycle.measuredX = measuredXYZ.x;
  cycle.measuredY = measuredXYZ.y;
  cycle.measuredZ = measuredXYZ.z;
}

function getRandomArbitrary(min, max) {
  return Math.random() * (max - min) + min;
}

function inspectionRotationError(e) {
  var rotVector = new Vector(0, 0, 0);
  // var randomI = getRandomArbitrary(0, 1);
  // var randomJ = getRandomArbitrary(0, 1);
  // var randomK = getRandomArbitrary(0, 1);
  switch (properties.rotationVector) {
  case "X":
    rotVector.x = 1;
    break;
  case "Y":
    rotVector.y = 1;
    break;
  case "Z":
    rotVector.z = 1;
    break;
  default:
    return;
  }
  // Random rotation vector
  // rotVector = new Vector(randomI, randomJ, randomK);
  //
  var eRad = toRad(e);
  var v = new Vector(measuredXYZ.x, measuredXYZ.y, measuredXYZ.z);
  var a = new Matrix(rotVector, eRad);
  var res = a.multiply(v);
  cycle.measuredX = res.x;
  cycle.measuredY = res.y;
  cycle.measuredZ = res.z;
}

function inspectionApplyErrors() {
  var e = getRandomArbitrary(properties.lowerDeviationAllowance, properties.upperDeviationAllowance);
  var randomEV = Vector.product(normalizedVector, e);
  switch (properties.deviationAllowanceType) {
  case "POINT Z VECTOR":
    cycle.measuredZ += randomEV.z;
    break;
  case "OFFSETX":
    cycle.measuredX += e;
    break;
  case "OFFSETXY":
    cycle.measuredX += e;
    cycle.measuredY += e;
    break;
  case "OFFSETXZ":
    cycle.measuredX += e;
    cycle.measuredZ += e;
    break;
  case "OFFSETY":
    cycle.measuredY += e;
    break;
  case "OFFSETYZ":
    cycle.measuredY += e;
    cycle.measuredZ += e;
    break;
  case "OFFSETZ":
    cycle.measuredZ += e;
    break;
  case "RANDOM":
    cycle.measuredX += randomEV.x;
    cycle.measuredY += randomEV.y;
    cycle.measuredZ += randomEV.z;
    break;
  case "ROTARY":
    inspectionRotationError(e);
    break;
  default:
    return;
  }
}

function inspectionWriteCADTransform() {
  var cadWorkPlane = currentSection.getModelPlane().getTransposed();
  var cadOrigin = currentSection.getModelOrigin().getNegated();
  var cadEuler = cadWorkPlane.getEuler2(EULER_XYZ_S);
  writeBlock(
    "G331" +
    " N" + pointNumber +
    " A" + abcFormat.format(cadEuler.x) +
    " B" + abcFormat.format(cadEuler.y) +
    " C" + abcFormat.format(cadEuler.z) +
    " X" + xyzFormat.format(cadOrigin.x) +
    " Y" + xyzFormat.format(cadOrigin.y) +
    " Z" + xyzFormat.format(cadOrigin.z)
  );
  if (hasParameter("autodeskcam:operation-id")) {
    writeComment("TOOLPATH " + getParameter("operation-comment"));
  }
}

function inspectionWriteWorkplaneTransform() {
  var euler = currentSection.workPlane.getEuler2(EULER_XYZ_S);
  var abc = new Vector(euler.x, euler.y, euler.z);
  writeBlock(
    "G330" +
    " N" + pointNumber +
    " A" + abcFormat.format(abc.x) +
    " B" + abcFormat.format(abc.y) +
    " C" + abcFormat.format(abc.z) +
    " X0 Y0 Z0 I0 R0"
  );
}

function inspectionWriteNominalData() {
  writeBlock(
    "G800" +
  " N" + pointNumber +
  " X" + xyzFormat.format(cycle.nominalX) +
  " Y" + xyzFormat.format(cycle.nominalY) +
  " Z" + xyzFormat.format(cycle.nominalZ) +
  " I" + ijkFormat.format(cycle.nominalI) +
  " J" + ijkFormat.format(cycle.nominalJ) +
  " K" + ijkFormat.format(cycle.nominalK) +
  conditional(hasParameter("operation:inspectSurfaceOffset"), " O" + xyzFormat.format(getParameter("operation:inspectSurfaceOffset"))) +
  conditional(hasParameter("operation:inspectUpperTolerance"), " U" + xyzFormat.format(getParameter("operation:inspectUpperTolerance"))) +
  conditional(hasParameter("operation:inspectLowerTolerance"), " L" + xyzFormat.format(getParameter("operation:inspectLowerTolerance")))
  );
}

function inspectionWriteMeasuredData() {
  writeBlock(
    "G801 N" + pointNumber +
    " X" + xyzFormat.format(cycle.measuredX) +
    " Y" + xyzFormat.format(cycle.measuredY) +
    " Z" + xyzFormat.format(cycle.measuredZ) +
    " R" + xyzFormat.format(tool.cornerRadius)
  );
  pointNumber += 1;
}

function onOpen() {
  return;
}

function onProbe() {
  return;
}

function onCycle() {
  return;
}

function onCyclePoint(x, y, z) {
  if (isFirstCyclePoint() || isLastCyclePoint()) {
    return;
  } else {
    inspectionCalculateVectors();
    inspectionCalculateNominals();
    inspectionRadiusOffset();
    inspectionCalculateMeasured();
    inspectionApplyErrors();
    inspectionWriteNominalData();
    inspectionWriteMeasuredData();
  }
}

function onCycleEnd() {
  return;
}

function onSection() {
  if (isInspectionOperation()) {
    inspectionCreateResultsFileHeader();
    if (hasParameter("autodeskcam:operation-id")) {
      writeln("TOOLPATHID " + getParameter("autodeskcam:operation-id"));
    }
    inspectionWriteCADTransform();
    inspectionWriteWorkplaneTransform();
  } else {
    return;
  }
}

function onSectionEnd() {
  if (isInspectionOperation() && (isLastSection() || getNextSection().getTool().number != tool.number)) {
    writeln("END");
  } else {
    return;
  }
}

function onClose() {
  return;
}
