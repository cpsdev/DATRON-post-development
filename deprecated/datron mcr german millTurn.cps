/**
  Copyright (C) 2012-2017 by Autodesk, Inc.
  All rights reserved.

  DATRON post processor configuration.

  $Revision$
  $Date$

  FORKID {9FA90B9F-51A1-4B08-9105-510C69047622}
*/

description = "Generic DATRON MCR Millturn (German)";
vendor = "DATRON";
vendorUrl = "http://www.datron.com";
legal = "Copyright (C) 2012-2017 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 24000;

longDescription = "Generic post for DATRON CNCs. This post works with all the common Datron CNCs like DATRON M7, DATRON M75, DATRON M10, DATRON M8Cube, and DATRON MLCube.";

extension = "mcr";
setCodePage("ascii");

capabilities = CAPABILITY_MILLING;
tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(90); // avoid potential center calculation errors for CNC
allowHelicalMoves = false;
allowedCircularPlanes =0;// (1 << PLANE_XY); // allow XY plane only

// user-defined properties
properties = {
  writeMachine: true, // write machine
  writeVersion: false, // include version info
  showOperationDialog: "dropdown", // shows a start dialog on the control to select the operation to start with
  useParametricFeed: true, // specifies that feed should be output using Q values
  showNotes: false, // specifies that operation notes should be output
  useSmoothing: true, // specifies if smoothing should be used or not
  useDynamic: true, // specifies using dynamic mode or not
  useParkPosition: true, // specifies to use park position at the end of the program
  useTimeStamp: false, // specifies to output time stamp
  language: "de", // specifies the language "en" or "de"
  writeCoolantCommands: false, // en/disable coolant code output for the entire program
  _got4thAxis: false, // specifies if the machine has a 4th axis
  _4thAxisRotatesAroundX: true, // specifies if the 4th axis rotates around X or Y
  _got5thAxis: false, // specifies if the machine has a 5th axis
  _MillTurn:true,
  _FeedPerTurn : 1
};

// user-defined property definitions
propertyDefinitions = {
  writeMachine: {title:"Write machine", description:"Output the machine settings in the header of the code.", group:0, type:"boolean"},
  writeVersion: {title:"Write version", description:"Write the version number in the header of the code.", group:0, type:"boolean"},
  showOperationDialog: {
    title: "Show operation dialog",
    description:"Shows a start dialog on the control which allows you to select the operation to start with.",
    type:"enum",
    values:[
      {id: "disabled", title: "Disabled"},
      {id: "dropdown", title:"Dropdown style"},
      {id: "checkbox", title:"Checkbox style"}
    ]
  },
  useParametricFeed:  {title:"Parametric feed", description:"Specifies the feed value that should be output using a Q value.", type:"boolean"},
  showNotes: {title:"Show notes", description:"Writes operation notes as comments in the outputted code.", type:"boolean"},
  useSmoothing: {title:"Use smoothing", description:"Enable to use smoothing in the NC program.", type:"boolean"},
  useDynamic: {title: "Use dynamic mode", description:"Enable to use dynamic mode.", type:"boolean"},
  useParkPosition: {title: "Park at end of program", description:"Enable to use the park position at end of program.", type:"boolean"},
  useTimeStamp: {title:"Use timestamp", description:"Enable to include timestamp in program header.", type:"boolean"},
  language: {title: "Language", description:"Specifies the language to use in the NC program.", type:"enum", values:[{id: "en", title: "English"}, {id: "de", title:"German"}]},
  writeCoolantCommands: {title:"Write coolant commands", description:"Enable/disable coolant code outputs for the entire program.", type:"boolean"},
  _got4thAxis: {title:"Has 4th axis", description:"Enable if the machine is equipped with a 4-axis.", type:"boolean"},
  _4thAxisRotatesAroundX: {title:"4th axis rotates around X", description:"Enable if the 4th axis rotates around the X axis, disable if it rotates around the Y axis.", type:"boolean"},
  _got5thAxis: {title:"Has 5th axis", description:"Enable if the machine is equipped with 5-axis capabilities.", type:"boolean"}
};

var mFormat = createFormat({prefix:"M", width:2, zeropad:true, decimals:1});

var xyzFormat = createFormat({decimals:(unit == MM ? 5 : 5), forceDecimal:false});
var angleFormat = createFormat({decimals:5, scale:DEG});
var abcFormat = createFormat({decimals:5, scale:DEG});
var feedFormat = createFormat({decimals:(unit == MM ? 2 : 2), scale:(unit == MM ? 0.001 : 1)});
var inverseTimeFormat = createFormat({decimals:5, scale:0.001});

var toolFormat = createFormat({decimals:0});
var rpmFormat = createFormat({decimals:0, scale:0.001});
var secFormat = createFormat({decimals:3, forceDecimal:true}); // seconds - range 0.001-99999.999
var milliFormat = createFormat({decimals:0}); // milliseconds // range 1-9999
var workpieceFormat = createFormat({decimals:(unit == MM ? 3 : 4), forceSign:true, width:7, trim:false});

var xOutput = createVariable({force:true}, xyzFormat);
var yOutput = createVariable({force:true}, xyzFormat);
var zOutput = createVariable({force:true}, xyzFormat);
var aOutput = createVariable({force:true}, abcFormat);
var bOutput = createVariable({force:true}, abcFormat);
var cOutput = createVariable({force:true}, abcFormat);
var feedOutput = createVariable({}, feedFormat);
var sOutput = createVariable({prefix:"S", force:true}, rpmFormat);

var gMotionModal = createModal({prefix:"Axyz ", force:true, suffix:","}, xyzFormat); // modal group 1 // G0-G3, ...

// fixed settings
var useRTCP = true; // en/disable calculation for having the datum origin out of center of rotary axis for 5 axis kinematics
var useInverseTimeFeed = false; // beta, keep false
var maxMaskLength = 40;

// collected state
var currentWorkOffset;
var currentFeedValue = -1;
var optionalSection = false;
var forceSpindleSpeed = false;
var activeMovements; // do not use by default
var currentFeedId;
var containsProbingOperations = false;

// format date + time
var timeFormat = createFormat({decimals:0, force:true, width:2, zeropad:true});
var now = new Date();
var nowDay = now.getDate();
var nowMonth = now.getMonth() + 1;
var nowHour = now.getHours();
var nowMin = now.getMinutes();
var nowSec = now.getSeconds();

// Start of multi-axis feedrate logic
/***** Be sure to add 'useInverseTime' to post properties if necessary. *****/
/***** 'inverseTimeOutput' must be defined. *****/
/***** 'headOffset' should be defined when a head rotary axis is defined. *****/
/***** The feedrate mode must be included in motion block output (linear, circular, etc. *****/
var dpmBPW = 0.1; // ratio of rotary accuracy to linear accuracy for DPM calculations
var inverseTimeUnits = 1.0; // 1.0 = minutes, 60.0 = seconds
var maxInverseTime = 45000; // maximum value to output for Inverse Time feeds

/** Calculate the multi-axis feedrate number. */
function getMultiaxisFeed(_x, _y, _z, _a, _b, _c, feed) {
  var f = {frn:0, fmode:0};
  if (feed <= 0) {
    error(localize("Feedrate is less than or equal to 0."));
    return f;
  }

  var length = getMoveLength(_x, _y, _z, _a, _b, _c);

  if (useInverseTimeFeed) { // inverse time
    f.frn = inverseTimeFormat.format(getInverseTime(length[0], feed));
    f.fmode = 93;
    feedOutput.reset();
  } else { // degrees per minute
    f.frn = feedOutput.format(getFeedDPM(length, feed));
    f.fmode = 94;
  }
  return f;
}

/** Calculate the DPM feedrate number. */
function getFeedDPM(_moveLength, _feed) {
  // moveLength[0] = Tool tip, [1] = XYZ, [2] = ABC

  if (currentSection.getOptimizedTCPMode() == 0) { // TCP mode is supported, output feed as FPM
    return _feed;
  } else { // DPM feedrate calculation
    var moveTime = ((_moveLength[0] < 1.e-6) ? 0.001 : _moveLength[0]) / _feed;
    var length = Math.sqrt(Math.pow(_moveLength[1], 2.0) + Math.pow((toDeg(_moveLength[2]) * dpmBPW), 2.0));
    return length / moveTime;
  }
}

/** Calculate the Inverse time feedrate number. */
function getInverseTime(_length, _feed) {
  var inverseTime;
  if (_length < 1.e-6) { // tool doesn't move
    if (typeof maxInverseTime === "number") {
      inverseTime = maxInverseTime;
    } else {
      inverseTime = 999999;
    }
  } else {
    inverseTime = _feed / _length / inverseTimeUnits;
    if (typeof maxInverseTime === "number") {
      if (inverseTime > maxInverseTime) {
        inverseTime = maxInverseTime;
      }
    }
  }
  return inverseTime;
}

/** Calculate the distance of the tool position to the center of a rotary axis. */
function getRotaryRadius(center, direction, toolPosition) {
  var normal = direction.getNormalized();
  var d1 = toolPosition.x - center.x;
  var d2 = toolPosition.y - center.y;
  var d3 = toolPosition.z - center.z;
  var radius = Math.sqrt(
    Math.pow((d1 * normal.y) - (d2 * normal.x), 2.0) +
    Math.pow((d2 * normal.z) - (d3 * normal.y), 2.0) +
    Math.pow((d3 * normal.x) - (d1 * normal.z), 2.0)
   );
  return radius;
}

/** Calculate the linear distance based on the rotation of a rotary axis. */
function getRadialDistance(axis, startTool, endTool, startABC, endABC) {
  // rotary axis does not exist
  if (!axis.isEnabled()) {
    return 0.0;
  }

  // calculate the rotary center based on head/table
  var center;
  if (axis.isHead()) {
    var pivot;
    if (typeof headOffset === "number") {
      pivot = headOffset;
    } else {
      pivot = tool.getBodyLength();
    }
    center = Vector.sum(startTool, Vector.product(machineConfiguration.getSpindleAxis(), pivot));
    center = Vector.sum(center, axis.getOffset());
  } else {
    center = axis.getOffset();
  }

  // calculate the radius of the tool end point compared to the rotary center
  var startRadius = getRotaryRadius(center, axis.getEffectiveAxis(), startTool);
  var endRadius = getRotaryRadius(center, axis.getEffectiveAxis(), endTool);

  // calculate length of radial move
  var radius = Math.max(startRadius, endRadius);
  var delta = Math.abs(endABC.getCoordinate(axis.getCoordinate()) - startABC.getCoordinate(axis.getCoordinate()));
  if (delta > Math.PI) {
    delta = 2 * Math.PI - delta;
  }
  var radialLength = (2 * Math.PI * radius) * (delta / (2 * Math.PI));
  return radialLength;
}

/** Calculate tooltip, XYZ, and rotary move lengths. */
function getMoveLength(_x, _y, _z, _a, _b, _c) {
  // get starting and ending positions
  var moveLength = new Array();
  var startTool;
  var endTool;
  var startXYZ;
  var endXYZ;
  var startABC = getCurrentDirection();
  var endABC = new Vector(_a, _b, _c);
  
  if (currentSection.getOptimizedTCPMode() == 0) {
    startTool = getCurrentPosition();
    endTool = new Vector(_x, _y, _z);
    startXYZ = machineConfiguration.getOrientation(startABC).getTransposed().multiply(startTool);
    endXYZ = machineConfiguration.getOrientation(endABC).getTransposed().multiply(endTool);
  } else {
    startXYZ = getCurrentPosition();
    endXYZ = new Vector(_x, _y, _z);
    startTool = machineConfiguration.getOrientation(startABC).multiply(startXYZ);
    endTool = machineConfiguration.getOrientation(endABC).multiply(endXYZ);
  }

  // calculate the radial portion of the move
  var radialLength = Math.sqrt(
    Math.pow(getRadialDistance(machineConfiguration.getAxisU(), startTool, endTool, startABC, endABC), 2.0) +
    Math.pow(getRadialDistance(machineConfiguration.getAxisV(), startTool, endTool, startABC, endABC), 2.0) +
    Math.pow(getRadialDistance(machineConfiguration.getAxisW(), startTool, endTool, startABC, endABC), 2.0)
  );

  // calculate the lengths of move
  // tool tip distance is the move distance based on a combination of linear and rotary axes movement
  var linearLength = Vector.diff(endXYZ, startXYZ).length;
  moveLength[0] = linearLength + radialLength;
  moveLength[1] = Vector.diff(endXYZ, startXYZ).length;
  moveLength[2] = 0;

  var start = new Array(startABC.x, startABC.y, startABC.z);
  var end = new Array(endABC.x, endABC.y, endABC.z);
  for (var i = 0; i < 3; ++i) {
    var delta = Math.abs(end[i] - start[i]);
    if (delta > Math.PI) {
      delta = 2 * Math.PI - delta;
    }
    moveLength[2] += Math.pow(delta, 2.0);
  }
  moveLength[2] = Math.sqrt(moveLength[2]);
  return moveLength;
}
// End of multi-axis feedrate logic

/**
  Writes the specified block.
*/
function writeBlock() {
  writeWords(arguments);
}

var charMap = {
  "\u00c4":"Ae",
  "\u00e4":"ae",
  "\u00dc":"Ue",
  "\u00fc":"ue",
  "\u00d6":"Oe",
  "\u00f6":"oe",
  "\u00df":"ss",
  "\u002d":"_"
};

/** Map specific chars. */
function mapComment(text) {
  var result = "";
  for (var i = 0; i < text.length; ++i) {
    var ch = charMap[text[i]];
    result += ch ? ch : text[i];
  }
  return result;
}

function formatComment(text) {
  return mapComment(text);
}

function formatVariable(text) {
  var mapped = mapComment(text.substring(0, 1).toUpperCase() + text.substring(1).toLowerCase());
  return mapped.replace(/[^A-Za-z0-9\-_]/g, "");
}

/**
  Output a comment.
*/
function writeComment(text) {
  writeln("; !" + formatComment(text) + "!");
}

function onOpen() {
  if (properties._got4thAxis || properties._got5thAxis) { // note: setup your machine here
    var aAxis;
    if (properties._got4thAxis && properties._got5thAxis) {
      aAxis = createAxis(
        {
          coordinate:properties._got5thAxis ? 0 : 1,
        table:true,
        axis:[properties._4thAxisRotatesAroundX ? -1 : 0, properties._4thAxisRotatesAroundX ? 0 : -1, 0],
        range:[properties._got5thAxis ? -100 : -360, properties._got5thAxis ? 0 : 360],
          preference:-1
        }
      );
    } else {
      aAxis = createAxis({coordinate:1, table:true, axis:[properties._4thAxisRotatesAroundX ? 1 : 0, properties._4thAxisRotatesAroundX ? 0 : 1, 0], range:[-360, 360], preference:1});
    }

    var cAxis = createAxis({coordinate:2, table:true, axis:[0, 0, -1], range:[-360, 360], cyclic:true, preference:0});

    if (properties._got4thAxis) {
      if (properties._got5thAxis) {
        machineConfiguration = new MachineConfiguration(aAxis, cAxis);
      } else {
        machineConfiguration = new MachineConfiguration(aAxis);
      }
    }
    
    setMachineConfiguration(machineConfiguration);
    optimizeMachineAngles2(1); // TCP mode
  }

  if (!machineConfiguration.isMachineCoordinate(0)) {
    aOutput.disable();
  }
  if (!machineConfiguration.isMachineCoordinate(1)) {
    bOutput.disable();
  }
  if (!machineConfiguration.isMachineCoordinate(2)) {
    cOutput.disable();
  }

  var numberOfSections = getNumberOfSections();
  for (var i = 0; i < numberOfSections; ++i) {
    var section = getSection(i);
    if (isProbeOperation(section)) {
      containsProbingOperations = true;
      break;
    }
  }

  // header
  writeProgramHeader();
}

function getOperationDescription(section) {
  var operationComment = "";
  if (section.hasParameter("operation-comment")) {
    operationComment = section.getParameter("operation-comment");
    operationComment = formatComment(operationComment);
  }

  var cycleTypeString = "";
  if (section.hasParameter("operation:cycleType")) {
    cycleTypeString = localize(section.getParameter("operation:cycleType")).toString();
    cycleTypeString = formatComment(cycleTypeString);
  }

  var sectionID = section.getId() + 1;
  var description = operationComment + "_" + cycleTypeString + "_" + sectionID;
  return description;
}

/** Writes the tool table. */
function writeToolTable() {
  var tools = getToolTable();
  writeBlock("; !" + translate("Number of tools in use") + ": " + tools.getNumberOfTools() + "!");
  if (tools.getNumberOfTools() > 0) {
    for (var i = 0; i < tools.getNumberOfTools(); ++i) {
      var tool = tools.getTool(i);
      var comment = "T" + (tool.number) + " = " + toolFormat.format(tool.number) + ";!" +
      formatComment(getToolTypeName(tool.type)) + " " +
      "D:" + xyzFormat.format(tool.diameter) + " " +
      "L2:" + xyzFormat.format(tool.fluteLength) + " " +
      "L3:" + xyzFormat.format(tool.shoulderLength) + "!";
      writeBlock(comment);
    }
  }
}

/** Writes the program header. */
function writeProgramHeader() {
  var date =  timeFormat.format(nowDay) + "." + timeFormat.format(nowMonth) + "." + now.getFullYear();
  var time = timeFormat.format(nowHour) + ":" + timeFormat.format(nowMin);

  if (properties.useTimeStamp) {
    writeBlock("!Makro file ; generated at " + date + " - " + time + " V9.09F!");
  } else {
    writeBlock("!Makro file ; V9.09F!");
  }
  if (programComment) {
    writeBlock("!" + formatComment(programComment) + "!");
  } else {
    writeBlock("!Makroprojekt description!");
  }
  writeln("");

  writeln("!Please make sure that the language on your control is set to " + "\"" + properties.language + "\"" + "!");
  switch (properties.language) {
  case "en":
    writeBlock("_sprache 1;");
    break;
  case "de":
    writeBlock("_sprache 0;");
    break;
  default:
    writeBlock("_sprache 1;");
  }

  writeln("");
  switch (unit) {
  case IN:
    writeBlock("Dimension 2;");
    break;
  case MM:
    writeBlock("Dimension 1;");
    break;
  }

  writeln("");

  var variablesDeclaration = new Array();
  var submacrosDeclaration = new Array();
  var dialogsDeclaration = new Array();
  
  if (properties.showOperationDialog != "disabled") {
    variablesDeclaration.push("optional_stop");
    if (properties.showOperationDialog == "checkbox") {
      if (getNumberOfSections() >= maxMaskLength) {
        submacrosDeclaration.push("Initvariables");
      }
    }
  }
  variablesDeclaration.push("$Message");

  dialogsDeclaration.push("_maske _haupt, " + "1000" + ", 0, " + "\"" + translate("Submacro") + " " + translate("Description") + "\"");
  if (properties.showOperationDialog != "disabled") {
    if (properties.showOperationDialog == "dropdown") {
    dialogsDeclaration.push("_feld optional_stop, 1, 0, 0, 0, 1, 2, 0," + " \"" + "optional_stop" + "\"" + "," + " \"" + "optional_stop" + "\"");
    } else {
      dialogsDeclaration.push("_feld optional_stop, 1, 0, 1, 0, 1, 2, 1," + " \"" + "optional_stop" + "\"" + "," + " \"" + "optional_stop" + "\"");
    }
  }

  //write variables declaration
  var tools = getToolTable();
  for (var i = 0; i < tools.getNumberOfTools(); ++i) {
    var tool = tools.getTool(i);
    variablesDeclaration.push("T" + tool.number);
  }

  var numberOfSections = getNumberOfSections();
  if (properties.showOperationDialog == "dropdown") {
    var dropDownElements = new Array();
    variablesDeclaration.push("startOperation");
  }
  
  var dropDownDialog = "_feld startOperation, 1, 0, 1, 0, 9999, 1, 0, \"Startoperation <";
 
  for (var i = 0; i < numberOfSections; ++i) {
    var section = getSection(i);
    var sectionID = i + 1;
    variablesDeclaration.push("Op_" + formatVariable(getOperationDescription(section)));
    submacrosDeclaration.push("Sm_" + formatVariable(getOperationDescription(section)));
    if (properties.showOperationDialog == "dropdown") {
      dropDownElements.push(formatVariable(getOperationDescription(section)) + "<" + sectionID + ">");
    } else if (properties.showOperationDialog == "checkbox") {
      if (getNumberOfSections() < maxMaskLength) {
        dialogsDeclaration.push("_feld Op_" + formatVariable(getOperationDescription(section)) + ", 1, 0, 1, 0, 1, 2, 1," + " \"" +
          formatVariable(getOperationDescription(section)) + "\"" + "," + " \"" +
          formatVariable(getOperationDescription(section)) + "\""
        );
      }
    }
    if (properties.useParametricFeed) {
      activeFeeds = initializeActiveFeeds(section);
      for (var j = 0; j < activeFeeds.length; ++j) {
        var feedContext = activeFeeds[j];
        var feedDescription = formatVariable(feedContext.description);
        if (variablesDeclaration.indexOf(feedDescription) == -1) {
          variablesDeclaration.push(feedDescription);
        }
      }
    }
  }
  
  if (properties.showOperationDialog == "dropdown") {
    dropDownDialog += dropDownElements.join(", ");
    dropDownDialog += ">\", \"Select the operation to start with. \"";
    dialogsDeclaration.push(dropDownDialog);
  }
  if (useRTCP && (properties._got4thAxis && properties._got5thAxis)) {
    variablesDeclaration.push("X_initial_pos");
    variablesDeclaration.push("Y_initial_pos");
    variablesDeclaration.push("Z_initial_pos");
    variablesDeclaration.push("A_initial_pos");
    variablesDeclaration.push("B_initial_pos");
    variablesDeclaration.push("C_initial_pos");
    variablesDeclaration.push("X_delta");
    variablesDeclaration.push("Y_delta");
    variablesDeclaration.push("Z_delta");
    variablesDeclaration.push("A_delta");
    variablesDeclaration.push("B_delta");
    variablesDeclaration.push("C_delta");
    variablesDeclaration.push("X");
    variablesDeclaration.push("Y");
    variablesDeclaration.push("Z");
    variablesDeclaration.push("A");
    variablesDeclaration.push("B");
    variablesDeclaration.push("C");
    variablesDeclaration.push("Israpid");
    variablesDeclaration.push("X_trans");
    variablesDeclaration.push("Y_trans");
    variablesDeclaration.push("Z_trans");
    variablesDeclaration.push("X_new");
    variablesDeclaration.push("Y_new");
    variablesDeclaration.push("Z_new");
    variablesDeclaration.push("X_temp");
    variablesDeclaration.push("Y_temp");
    variablesDeclaration.push("Z_temp");
    variablesDeclaration.push("A_temp");
    variablesDeclaration.push("B_temp");
    variablesDeclaration.push("C_temp");
    variablesDeclaration.push("Isinitialposition");
    variablesDeclaration.push("timefeed");

    submacrosDeclaration.push("Initposition");
    submacrosDeclaration.push("Endmacro");
  }
  if ( properties._MillTurn){
  	variablesDeclaration.push("Cpos");
  }

  if (useRTCP && (properties._got4thAxis && properties._got5thAxis)) {
    submacrosDeclaration.push("Transformpath");
  }
  if (useRTCP && (properties._got4thAxis && properties._got5thAxis)) {
    submacrosDeclaration.push("Transformoffset");
  }
  

  submacrosDeclaration.push("Retractzmax");
  variablesDeclaration.push("Curr_zpno");
  variablesDeclaration.push("Zpos");

  if (containsProbingOperations) {
    variablesDeclaration.push("Xvalue1");
    variablesDeclaration.push("Xvalue2");
    variablesDeclaration.push("Yvalue1");
    variablesDeclaration.push("Yvalue2");
    variablesDeclaration.push("Zvalue");
    variablesDeclaration.push("Newpos");
    variablesDeclaration.push("Rotationvalue");
  }

  writeBlock("Variable " + variablesDeclaration.join(", ") + ";");
  writeln("");
  writeBlock("Smakros " + submacrosDeclaration.join(", ") + ";");
  writeln("");
  writeBlock(dialogsDeclaration.join(EOL) + ";");
  writeln("");

  if (useRTCP && (properties._got4thAxis && properties._got5thAxis)) {
    writeBlock("_exit Endmacro;");
    writeln("");
  }

  if (useRTCP && (properties._got4thAxis && properties._got5thAxis)) {
    writeBlock("_maske Transformoffset, 4, 0, \"create a new coordinate system with the given rotation values\"");
    writeBlock("_feld A, 4, 8, 0, -9999, 9999, 0, 1, \"alpha\", \"rotation around x axis\"");
    writeBlock("_feld B, 4, 8, 0, -9999, 9999, 0, 1, \"beta\", \"rotation around Y\"");
    writeBlock("_feld C, 4, 8, 0, -9999, 9999, 0, 1, \"gamma\", \"rotation around Z\";");
    writeln("");
    writeBlock("_maske Transformpath, 9, 0, \"create a new coordinate system with the given rotation values\"");
    writeBlock("_feld Israpid, 4, 5, 0, -9999, 9999, 2, 0, \"Is rapid\", \"is rapid\"");
    writeBlock("_feld Isinitialposition, 4, 3, 0, -9999, 9999, 2, 1, \"Isinitialposition\", \"If set machine positioning with z max height\"");
    writeBlock("_feld X, 4, 5, 0, -9999, 9999, 0, 1, \"X Value\", \"X Position\"");
    writeBlock("_feld Y, 4, 5, 0, -9999, 9999, 0, 1, \"Y Value\", \"Y Position\"");
    writeBlock("_feld Z, 4, 5, 0, -9999, 9999, 0, 1, \"Z Value\", \"Z Position\"");
    writeBlock("_feld A, 4, 8, 0, -9999, 9999, 0, 1, \"alpha\", \"rotation around x axis\"");
    writeBlock("_feld B, 4, 8, 0, -9999, 9999, 0, 1, \"beta\", \"rotation around Y\"");
    writeBlock("_feld C, 4, 8, 0, -9999, 9999, 0, 1, \"gamma\", \"rotation around Z\"");
    writeBlock("_feld timefeed, 4, 8, 0, 0, " + maxInverseTime + ", 0, 1, \"time in seconds\", \"movement duration for the current line segment\";");
    writeln("");
  }

  if (properties.showOperationDialog == "checkbox") {
    if (numberOfSections >= maxMaskLength) {
      writeBlock("(");
      for (var i = 0; i < numberOfSections; ++i) {
        var section = getSection(i);
        writeBlock("Op_" + formatVariable(getOperationDescription(section)) + " = 1");
      }
      writeln(") Initvariables;");
    }
  }
  if (useRTCP && (properties._got4thAxis && properties._got5thAxis)) {
    createPositionInitSubmacro();
    createEndmacro();
  }

  if (useRTCP && (properties._got4thAxis && properties._got5thAxis)) {
    createRtcpTransformationSubmacro();
  }

  if (useRTCP && (properties._got4thAxis && properties._got5thAxis)) {
    createRtcpSimuSubmacro();
  }

  createRetractMacro();
}

function writeMainProgram() {

  var numberOfSections = getNumberOfSections();
  if (properties.showOperationDialog == "checkbox") {
    if (numberOfSections >= maxMaskLength) {
      writeBlock(translate("Submacro") + " Initvariables;");
    }
  }

  for (var i = 0; i < numberOfSections; ++i) {
    var section = getSection(i);
    var Description = getOperationDescription(section);
    var sectionID = i+1;

    var sectionName = formatVariable("Sm_" + Description);
    var maskName = formatVariable("Op_" + Description);

    writeComment("##########" + Description + "##########");
    if (properties.showOperationDialog == "checkbox") {
      writeBlock(translate("Condition") + " " + maskName + ", 0, 1, 0, " + sectionID + ";");
    } else if (properties.showOperationDialog == "dropdown") {
      writeBlock(translate("Label") + " " + sectionID + ";");
    }

    var tool = section.getTool();
    if (properties.showNotes && section.hasParameter("notes")) {
      var notes = section.getParameter("notes");
      if (notes) {
        var lines = String(notes).split("\n");
        var r1 = new RegExp("^[\\s]+", "g");
        var r2 = new RegExp("[\\s]+$", "g");
        for (line in lines) {
          var comment = lines[line].replace(r1, "").replace(r2, "");
          if (comment) {
            writeComment(comment);
          }
        }
      }
    }
    var showToolZMin = true;
    if (showToolZMin) {
      if (is3D()) {
        var zRange = section.getGlobalZRange();
        var number = tool.number;
        if (section.getTool().number != number) {
          break;
        }
        zRange.expandToRange(section.getGlobalZRange());
        writeln(localize("; ! ZMIN") + " = " + xyzFormat.format(zRange.getMinimum()) + "!");
      }
    }
    if (!isProbeOperation(section)) {
      writeBlock(translate("Tool") + " T" + (tool.number) + ", 0, 0, 1, 0;");
      if (tool.spindleRPM < 6000) {
        tool.spindleRPM = 6000;
      }
      onSpindleSpeed(tool.spindleRPM);
    }

    // set coolant after we have positioned at Z
    setCoolant(tool.coolant);
    var t = tolerance;
    if (section.hasParameter("operation:tolerance")) {
      t = section.getParameter("operation:tolerance");
    }
    if (properties.useDynamic) {
      var dynamic = 5;
      if (t <= 0.02) {
        dynamic = 4;
      }
      if (t <= 0.01) {
        dynamic = 3;
      }
      if (t <= 0.005) {
        dynamic = 2;
      }
      if (t <= 0.003) {
        dynamic = 1;
      }
      writeBlock(translate("Dynamics")  + " " + dynamic + ";");
    }
    if (properties.useParametricFeed) {
      activeFeeds = initializeActiveFeeds(section);
      for (var j = 0; j < activeFeeds.length; ++j) {
        var feedContext = activeFeeds[j];
        writeBlock(formatVariable(feedContext.description) + " = " + feedFormat.format(feedContext.feed) + (unit == MM ? ";!m/min!" : ";!inch/min!"));
      }
    }

    // wcs
    var workOffset = section.workOffset;
    if (workOffset != 0 && workOffset < 41) {
      workOffset = (properties._got4thAxis && properties._got5thAxis) ? 19 : workOffset;
      if (workOffset != currentWorkOffset) {
        writeBlock("Position " + workOffset + ", 2;");
        currentWorkOffset = workOffset;
      }
    }

    writeBlock(translate("Submacro") + " " + sectionName + ";");
    if (properties.showOperationDialog == "checkbox") {
      writeBlock(translate("Label") + " " + sectionID + ";");
    }
  }
}

function writeWorkpiece() {
  var workpiece = getWorkpiece();
  var delta = Vector.diff(workpiece.upper, workpiece.lower);

  writeBlock("; !" + translate("Workpiece dimensions") + ":!");
  writeBlock(
    "; !min:     X: " + workpieceFormat.format(workpiece.lower.x) + ";" +
    " Y: " + workpieceFormat.format(workpiece.lower.y) + ";" +
    " Z: " + workpieceFormat.format(workpiece.lower.z) + "!"
  );
  writeBlock(
    "; !max:     X: " + workpieceFormat.format(workpiece.upper.x) + ";" +
    " Y: " + workpieceFormat.format(workpiece.upper.y) + ";" +
    " Z: " + workpieceFormat.format(workpiece.upper.z) + "!"
  );
  writeBlock(
    "; !" + translate("Part size") + " X: " + workpieceFormat.format(delta.x) + ";" +
    " Y: " + workpieceFormat.format(delta.y) + ";" +
    " Z: " + workpieceFormat.format(delta.z) + "!"
  );

  // insert maximum deep of the hole program

  writeBlock(
    "Wdef " +
    xyzFormat.format(delta.getX()) + ", " +
    xyzFormat.format(delta.getY()) + ", " +
    xyzFormat.format(delta.getZ()) + ", " +
    xyzFormat.format(workpiece.lower.x) + ", " +
    xyzFormat.format(workpiece.lower.y) + ", " +
    xyzFormat.format(workpiece.upper.z) + ", 0;"
  );
}

function onComment(message) {
  var comments = String(message).split(";");
  for (comment in comments) {
    writeComment(comments[comment]);
  }
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}

/** Force output of A, B, and C. */
function forceABC() {
  aOutput.reset();
  bOutput.reset();
  cOutput.reset();
}

function forceFeed() {
  currentFeedId = undefined;
  feedOutput.reset();
  currentFeedValue = -1;
}

/** Force output of X, Y, Z, A, B, C, and F on next output. */
function forceAny() {
  forceXYZ();
  forceABC();
  forceFeed();
}

function FeedContext(id, description, feed) {
  this.id = id;
  this.description = description;
  if (revision < 41759) {
    this.feed = (unit == MM ? feed : toPreciseUnit(feed, MM)); // temporary solution
  } else {
    this.feed = feed;
  }
}

/** Maps the specified feed value to Q feed or formatted feed. */
function getFeed(f) {
  if (activeMovements) {
    var feedContext = activeMovements[movement];
    if (feedContext != undefined) {
      if (!feedFormat.areDifferent(feedContext.feed, f)) {
        if (feedContext.id == currentFeedId) {
          return ""; // nothing has changed
        }
        forceFeed();
        currentFeedId = feedContext.id;
        return (translate("Feed") + " " + formatVariable(feedContext.description) + (Array(4).join(", " + formatVariable(feedContext.description))) + ";");
      }
    }
    currentFeedId = undefined; // force Q feed next time
  }
  if (feedFormat.areDifferent(currentFeedValue, f)) {
    currentFeedValue = f;
    return translate("Feed") + " " + feedOutput.format(f) + Array(4).join(", " + feedFormat.format(f)) + ";";
  }
  return "";
}

function initializeActiveFeeds(section) {
  var activeFeeds = new Array();
  if (section.hasAnyCycle && section.hasAnyCycle()) {
    return activeFeeds;
  }
  activeMovements = new Array();
  var movements = section.getMovements();

  var id = 0;


  if (section.hasParameter("operation:tool_feedCutting")) {
    if (movements & ((1 << MOVEMENT_CUTTING) | (1 << MOVEMENT_LINK_TRANSITION) | (1 << MOVEMENT_EXTENDED))) {
      var feedContext = new FeedContext(id, localize("Cutting"), section.getParameter("operation:tool_feedCutting"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_CUTTING] = feedContext;
      activeMovements[MOVEMENT_LINK_TRANSITION] = feedContext;
      activeMovements[MOVEMENT_EXTENDED] = feedContext;
    }
    ++id;
    if (movements & (1 << MOVEMENT_PREDRILL)) {
      feedContext = new FeedContext(id, localize("Predrilling"), section.getParameter("operation:tool_feedCutting"));
      activeMovements[MOVEMENT_PREDRILL] = feedContext;
      activeFeeds.push(feedContext);
    }
    ++id;

    if (section.hasParameter("operation-strategy") && (section.getParameter("operation-strategy") == "drill")) {
      var feedContext = new FeedContext(id, localize("Cutting"), section.getParameter("operation:tool_feedCutting"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_CUTTING] = feedContext;
    }
    ++id;
  }

  if (section.hasParameter("operation:finishFeedrate")) {
    if (movements & (1 << MOVEMENT_FINISH_CUTTING)) {
      var feedContext = new FeedContext(id, localize("Finish"), section.getParameter("operation:finishFeedrate"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_FINISH_CUTTING] = feedContext;
    }
    ++id;
  } else if (section.hasParameter("operation:tool_feedCutting")) {
    if (movements & (1 << MOVEMENT_FINISH_CUTTING)) {
      var feedContext = new FeedContext(id, localize("Finish"), section.getParameter("operation:tool_feedCutting"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_FINISH_CUTTING] = feedContext;
    }
    ++id;
  }

  if (section.hasParameter("operation:tool_feedEntry")) {
    if (movements & (1 << MOVEMENT_LEAD_IN)) {
      var feedContext = new FeedContext(id, localize("Entry"), section.getParameter("operation:tool_feedEntry"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_LEAD_IN] = feedContext;
    }
    ++id;
  }

  if (section.hasParameter("operation:tool_feedExit")) {
    if (movements & (1 << MOVEMENT_LEAD_OUT)) {
      var feedContext = new FeedContext(id, localize("Exit"), section.getParameter("operation:tool_feedExit"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_LEAD_OUT] = feedContext;
    }
    ++id;
  }

  if (section.hasParameter("operation:noEngagementFeedrate")) {
    if (movements & (1 << MOVEMENT_LINK_DIRECT)) {
      var feedContext = new FeedContext(id, localize("Direct"), section.getParameter("operation:noEngagementFeedrate"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_LINK_DIRECT] = feedContext;
    }
    ++id;
  } else if (section.hasParameter("operation:tool_feedCutting") &&
    section.hasParameter("operation:tool_feedEntry") &&
    section.hasParameter("operation:tool_feedExit")) {
    if (movements & (1 << MOVEMENT_LINK_DIRECT)) {
      var feedContext = new FeedContext(id, localize("Direct"), Math.max(section.getParameter("operation:tool_feedCutting"), section.getParameter("operation:tool_feedEntry"), section.getParameter("operation:tool_feedExit")));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_LINK_DIRECT] = feedContext;
    }
    ++id;
  }

  if (section.hasParameter("operation:reducedFeedrate")) {
    if (movements & (1 << MOVEMENT_REDUCED)) {
      var feedContext = new FeedContext(id, localize("Reduced"), section.getParameter("operation:reducedFeedrate"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_REDUCED] = feedContext;
    }
    ++id;
  }

  if (section.hasParameter("operation:tool_feedRamp")) {
    if (movements & ((1 << MOVEMENT_RAMP) | (1 << MOVEMENT_RAMP_HELIX) | (1 << MOVEMENT_RAMP_PROFILE) | (1 << MOVEMENT_RAMP_ZIG_ZAG))) {
      var feedContext = new FeedContext(id, localize("Ramping"), section.getParameter("operation:tool_feedRamp"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_RAMP] = feedContext;
      activeMovements[MOVEMENT_RAMP_HELIX] = feedContext;
      activeMovements[MOVEMENT_RAMP_PROFILE] = feedContext;
      activeMovements[MOVEMENT_RAMP_ZIG_ZAG] = feedContext;
    }
    ++id;
  }
  if (section.hasParameter("operation:tool_feedPlunge")) {
    if (movements & (1 << MOVEMENT_PLUNGE)) {
      var feedContext = new FeedContext(id, localize("Plunge"), section.getParameter("operation:tool_feedPlunge"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_PLUNGE] = feedContext;
    }
    ++id;
  }
  if (true) { // high feed
    if (movements & (1 << MOVEMENT_HIGH_FEED)) {
      var feedContext = new FeedContext(id, localize("High Feed"), this.highFeedrate);
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_HIGH_FEED] = feedContext;
    }
    ++id;
  }
  return activeFeeds;
}

var currentWorkPlaneABC = undefined;

function forceWorkPlane() {
  currentWorkPlaneABC = undefined;
}

/*
function onRewindMachine() {
  writeComment("REWIND");
}
*/

function setWorkPlane(abc) {
  forceWorkPlane(); // always need the new workPlane

  if (!machineConfiguration.isMultiAxisConfiguration()) {
    return; // ignore
  }

  if (!((currentWorkPlaneABC == undefined) ||
        abcFormat.areDifferent(abc.x, currentWorkPlaneABC.x) ||
        abcFormat.areDifferent(abc.y, currentWorkPlaneABC.y) ||
        abcFormat.areDifferent(abc.z, currentWorkPlaneABC.z))) {
    return; // no change
  }

  gMotionModal.reset();
  if (useRTCP && (properties._got4thAxis && properties._got5thAxis)) {
    writeBlock("A_temp = " + (machineConfiguration.isMachineCoordinate(0) ? abcFormat.format(abc.x) : "a6p") + " - A_delta;");
    writeBlock("B_temp = " + (machineConfiguration.isMachineCoordinate(1) ? abcFormat.format(abc.y) : "b6p") + " - B_delta;");
    writeBlock("C_temp = " + (machineConfiguration.isMachineCoordinate(2) ? abcFormat.format(abc.z) : "c6p") + " - C_delta;");
    writeBlock("Axyzabc 1, x6p, y6p, z6p, A_temp, B_temp, C_temp;");
    //writeBlock("Axyzabc 1, x6p, y6p, z6p, a6p, " + (machineConfiguration.isMachineCoordinate(1) ? abcFormat.format(abc.y) : "b6p") + ", c6p;");
    if (machineConfiguration.isMultiAxisConfiguration() && !currentSection.isMultiAxis()) {
      writeBlock(translate("Submacro") + " Transformoffset 0, ",
      abcFormat.format(abc.x) +", ",
      abcFormat.format(abc.y) +", ",
      abcFormat.format(abc.z) +";");
    }
  } else {
    var a = (machineConfiguration.isMachineCoordinate(0) ? aOutput.format(abc.x) : "a6p");
    var b = (machineConfiguration.isMachineCoordinate(1) ? bOutput.format(abc.y) : "b6p");
    var c = (machineConfiguration.isMachineCoordinate(2) ? cOutput.format(abc.z) : "c6p");
    writeBlock("Axyzabc 1, x6p, y6p, z6p, " + a + ", " + b + ", " +  c + ";");
  }
  currentWorkPlaneABC = abc;
}

var closestABC = false; // choose closest machine angles
var currentMachineABC;

function getWorkPlaneMachineABC(workPlane) {
  var W = workPlane; // map to global frame

  var abc = machineConfiguration.getABC(W);
  if (closestABC) {
    if (currentMachineABC) {
      abc = machineConfiguration.remapToABC(abc, currentMachineABC);
    } else {
      abc = machineConfiguration.getPreferredABC(abc);
    }
  } else {
    abc = machineConfiguration.getPreferredABC(abc);
  }

  try {
    abc = machineConfiguration.remapABC(abc);
    currentMachineABC = abc;
  } catch (e) {
    error(
      localize("Machine angles not supported") + ":"
      + conditional(machineConfiguration.isMachineCoordinate(0), " A" + abcFormat.format(abc.x))
      + conditional(machineConfiguration.isMachineCoordinate(1), " B" + abcFormat.format(abc.y))
      + conditional(machineConfiguration.isMachineCoordinate(2), " C" + abcFormat.format(abc.z))
    );
    return undefined;
  }

  var direction = machineConfiguration.getDirection(abc);
  if (!isSameDirection(direction, W.forward)) {
    error(localize("Orientation not supported."));
    return undefined;
  }

  if (!machineConfiguration.isABCSupported(abc)) {
    error(
      localize("Work plane is not supported") + ":"
      + conditional(machineConfiguration.isMachineCoordinate(0), " A" + abcFormat.format(abc.x))
      + conditional(machineConfiguration.isMachineCoordinate(1), " B" + abcFormat.format(abc.y))
      + conditional(machineConfiguration.isMachineCoordinate(2), " C" + abcFormat.format(abc.z))
    );
    return undefined;
  }

  var tcp = false;
  if (tcp) {
    setRotation(W); // TCP mode
  } else {
    var O = machineConfiguration.getOrientation(abc);
    var R = machineConfiguration.getRemainingOrientation(abc, W);
    setRotation(R);
  }

  return abc;
}

function createRtcpSimuSubmacro() {

  writeBlock("(");
  if (useInverseTimeFeed) {
    writeBlock(translate("Feed") + " timefeed" + (Array(4).join(", timefeed")) + ";");
  }
  
  writeBlock("X_temp = X_delta;");
  writeBlock("Y_temp = Y_delta;");
  writeBlock("Z_temp = Z_delta;");

  if (properties._got5thAxis) {
    writeBlock(";!Rotation around C!;");
    writeBlock("X_trans = X_temp * Cos ( C ) - Y_temp * Sin ( C );");
    writeBlock("Y_trans = X_temp * Sin ( C ) + Y_temp * Cos ( C );");
    writeBlock("Z_trans = Z_temp;");
    writeBlock("X_temp = X_trans;");
    writeBlock("Y_temp = Y_trans;");
    writeBlock("Z_temp = Z_trans;");
  }
  
  writeBlock(";!Rotation around A!;");
  writeBlock("X_trans = X_temp;");
  writeBlock("Y_trans = Y_temp * Cos ( A ) - Z_temp * Sin ( A );");
  writeBlock("Z_trans = Y_temp * Sin ( A ) + Z_temp * Cos ( A );");
  writeBlock("X_temp = X_trans;");
  writeBlock("Y_temp = Y_trans;");
  writeBlock("Z_temp = Z_trans;");

  // writeBlock(";!Rotation around B!;");
  // writeBlock("X_trans = Z_temp * Sin ( B ) + X_temp * Cos ( B );");
  // writeBlock("Y_trans = Y_temp;");
  // writeBlock("Z_trans = Z_temp * Cos ( B ) - X_temp * Sin ( B );");
  // writeBlock("X_temp = X_trans;");
  // writeBlock("Y_temp = Y_trans;");
  // writeBlock("Z_temp = Z_trans;");

  writeBlock(";!Calc new Position!;");
  writeBlock("X_new = X - X_trans;");
  writeBlock("Y_new = Y - Y_trans;");
  writeBlock("Z_new = ( ( Isinitialposition + 1 ) % 2 ) * ( Z - Z_trans ) + Isinitialposition * Z6max;");

  writeBlock("A_temp =  A - A_delta;");
  writeBlock("B_temp = B - B_delta;");
  writeBlock("C_temp = C - C_delta;");

  if (properties._got4thAxis && properties._got5thAxis) {
     writeBlock("Axyzabc Israpid, X_new, Y_new, Z_new, A_temp, 0, C_temp;");
  } else {
     writeBlock("Axyzabc Israpid, X_new, Y_new, Z_new, 0, A_temp, 0;");
  }

  writeBlock(") Transformpath;");

}

function createRtcpTransformationSubmacro() {
  writeBlock("(");
  writeBlock("Position 19, 2;");
/*
  if (properties._got5thAxis) {
     writeBlock("Position 19, 2;");
  } else if (properties._got4thAxis && properties._got5thAxis) {
    writeBlock("Position 21, 2;");
  }
*/
  writeBlock("X_temp = X_delta;");
  writeBlock("Y_temp = Y_delta;");
  writeBlock("Z_temp = Z_delta;");

  writeBlock(";!Rotation around C!;");
  writeBlock("X_trans = X_temp * Cos ( C ) - Y_temp * Sin ( C );");
  writeBlock("Y_trans = X_temp * Sin ( C ) + Y_temp * Cos ( C );");
  writeBlock("Z_trans = Z_temp;");
  writeBlock("X_temp = X_trans;");
  writeBlock("Y_temp = Y_trans;");
  writeBlock("Z_temp = Z_trans;");

  writeBlock(";!Rotation around A!;");
  writeBlock("X_trans = X_temp;");
  writeBlock("Y_trans = Y_temp * Cos ( A ) - Z_temp * Sin ( A );");
  writeBlock("Z_trans = Y_temp * Sin ( A ) + Z_temp * Cos ( A );");
  writeBlock("X_temp = X_trans;");
  writeBlock("Y_temp = Y_trans;");
  writeBlock("Z_temp = Z_trans;");

  // writeBlock(";!Rotation around B!;");
  // writeBlock("X_trans = Z_temp * Sin ( B ) + X_temp * Cos ( B );");
  // writeBlock("Y_trans = Y_temp;");
  // writeBlock("Z_trans = Z_temp * Cos ( B ) - X_temp * Sin ( B );");
  // writeBlock("X_temp = X_trans;");
  // writeBlock("Y_temp = Y_trans;");
  // writeBlock("Z_temp = Z_trans;");

  writeBlock(";!Calc new Position!;");
  writeBlock("X_new = X6p + X_trans;");
  writeBlock("Y_new = Y6p + Y_trans;");
  writeBlock("Z_new = Z6p + Z_trans;");
  writeBlock(";!set new position!;");
  writeBlock(translate("Setzp") + " X_new, Y_new, Z_new;");
  writeBlock(") Transformoffset;");
}

function createPositionInitSubmacro() {
  // get initial offset
  writeBlock("(");
  writeBlock("X_initial_pos = X6p;");
  writeBlock("Y_initial_pos = Y6p;");
  writeBlock("Z_initial_pos = Z6p;");
  writeBlock("A_initial_pos = A6p;");
  writeBlock("B_initial_pos = B6p;");
  writeBlock("C_initial_pos = C6p;");

  writeBlock("Position 19, 2;");
/*
  if (properties._got5thAxis) {
     writeBlock("Position 19, 2;");
  } else if (properties._got4thAxis && properties._got5thAxis) {
    writeBlock("Position 21, 2;");
  }
*/
  writeBlock("X_delta = X_initial_pos - X6p;");
  writeBlock("Y_delta = Y_initial_pos - Y6p;");
  writeBlock("Z_delta = Z_initial_pos - Z6p;");
  writeBlock("A_delta = A_initial_pos - A6p;");
  writeBlock("B_delta = B_initial_pos - B6p;");
  writeBlock("C_delta = C_initial_pos - C6p;");
  writeBlock(") Initposition;");
}

function createRetractMacro() {
  writeBlock("(");
  writeBlock("Curr_zpno = Zeromemnr;");
  writeBlock(translate("Zeromem") + " 0;");
  writeBlock("Zpos = - Wzl - " + (unit == MM ? 10 : 0.5) + ";");
  writeBlock("Axyz 1, Xp, Yp, Zpos, 0, 0;");
  writeBlock(translate("Zeromem") + " Curr_zpno;");
  writeBlock(") Retractzmax;");
}


function createEndmacro() {
  writeBlock("(");
  if (useInverseTimeFeed) {
    mcrSetTimeFeed();
  }
  writeBlock(translate("Submacro") + " Transformoffset 0, 0, 0, 0;");
  writeBlock(") Endmacro;");
}

function isProbeOperation(section) {
  return section.hasParameter("operation-strategy") && (section.getParameter("operation-strategy") == "probe");
}

function onSection() {
  var forceToolAndRetract = optionalSection && !currentSection.isOptional();
  optionalSection = currentSection.isOptional();

  var insertToolCall = forceToolAndRetract || isFirstSection() ||
    currentSection.getForceToolChange && currentSection.getForceToolChange() ||
    (tool.number != getPreviousSection().getTool().number);

  var retracted = false; // specifies that the tool has been retracted to the safe plane
  var newWorkOffset = isFirstSection() ||
    (getPreviousSection().workOffset != currentSection.workOffset); // work offset changes
  var newWorkPlane = isFirstSection() ||
    !isSameDirection(getPreviousSection().getGlobalFinalToolAxis(), currentSection.getGlobalInitialToolAxis()) ||
    (currentSection.isOptimizedForMachine() && getPreviousSection().isOptimizedForMachine() &&
    Vector.diff(getPreviousSection().getFinalToolAxisABC(), currentSection.getInitialToolAxisABC()).length > 1e-4) ||
    (!machineConfiguration.isMultiAxisConfiguration() && currentSection.isMultiAxis());

  writeBlock("(");
  if (isProbeOperation(currentSection)) {
    writeBlock("T3d 9, 0, 1, 15, 17, 10, 10, 10, 10, 10, 10;"); // enable probe
    writeBlock(translate("Rpm") + " 0, 30, 0, 30;");
  } else {
    writeBlock("T3d 0, 0, 1, 15, 17, 10, 10, 10, 10, 10, 10;"); // disable probe
  }

  if (newWorkOffset || newWorkPlane) {
    // retract to safe plane
    retracted = true;
    writeBlock(translate("Submacro") + " Retractzmax;");
    forceXYZ();
  }

  if (insertToolCall) {
    forceWorkPlane();

    if (tool.number > 99) {
      warning(localize("Tool number exceeds maximum value."));
    }
  }

  if (insertToolCall ||
      forceSpindleSpeed ||
      isFirstSection() ||
      (rpmFormat.areDifferent(tool.spindleRPM, sOutput.getCurrent())) ||
      (tool.clockwise != getPreviousSection().getTool().clockwise)) {
    forceSpindleSpeed = false;

    if (tool.spindleRPM < 6000) {
      tool.spindleRPM = 6000;
    }
    if (tool.spindleRPM > 60000) {
      warning(localize("Spindle speed exceeds maximum value."));
    }
    if (!tool.clockwise) {
      error(localize("Spindle direction not supported."));
      return;
    }

    //onCommand(COMMAND_START_CHIP_TRANSPORT);
    if (!is3D() || machineConfiguration.isMultiAxisConfiguration()) {
      // writeBlock(mFormat.format(xxx)); // shortest path traverse
    }
  }

  forceXYZ();

  if (machineConfiguration.isMultiAxisConfiguration()) { // use 5-axis indexing for multi-axis mode
    // set working plane after datum shift

    if (currentSection.isMultiAxis()) {
      forceWorkPlane();
      cancelTransformation();
      var abc = currentSection.getInitialToolAxisABC();
      setWorkPlane(abc); // pre-positioning ABC
    } else {
      var abc = new Vector(0, 0, 0);
      abc = getWorkPlaneMachineABC(currentSection.workPlane);
      setWorkPlane(abc);
    }
  } else { // pure 3D
    var remaining = currentSection.workPlane;
   
    setRotation(remaining);
  }

  forceAny();

  var t = tolerance;
  if (hasParameter("operation:tolerance")) {
    if (t < getParameter("operation:tolerance")) {
      t = getParameter("operation:tolerance");
    }
  }
  if (properties.useSmoothing && !currentSection.isMultiAxis() && !isProbeOperation(currentSection)) {
    writeBlock(translate("Contour_smoothing") + " 1, " + xyzFormat.format(t * 1.2) + ", 0.1, 110, 1;");
  }

  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  if (!retracted) {
    if (getCurrentPosition().z < initialPosition.z) {
      writeBlock(translate("Submacro") + " Retractzmax;");
    }
  }

  if (currentSection.isMultiAxis() && (currentSection.getOptimizedTCPMode() == 0)) {
    writeBlock("rtcp 1;");
  }

  if (currentSection.isMultiAxis()) {
    var abc = currentSection.getInitialToolAxisABC();
    var a = (machineConfiguration.isMachineCoordinate(0) ? aOutput.format(abc.x) : "a6p");
    var b = (machineConfiguration.isMachineCoordinate(1) ? bOutput.format(abc.y) : "b6p");
    var c = (machineConfiguration.isMachineCoordinate(2) ? cOutput.format(abc.z) : "c6p");

    if (useRTCP && (properties._got4thAxis && properties._got5thAxis)) {
      writeBlock("Position 19, 2;");
      /*
      if (properties._got5thAxis) {
         writeBlock("Position 19, 2;");
      } else if (properties._got4thAxis && properties._got5thAxis) {
        writeBlock("Position 21, 2;");
      }
      */
      writeBlock(translate("Submacro") + " Retractzmax;");
      writeBlock(translate("Submacro") + " Transformpath 0, 1, 1, " +
        xOutput.format(initialPosition.x) + ", " +
        yOutput.format(initialPosition.y) + ", " +
        "z6p" + ", " +
        a + ", " +
        b + ", " +
        c + ",0;"
      );
      writeBlock(translate("Submacro") + " Transformpath 0, 1, 0, " +
        xOutput.format(initialPosition.x) + ", " +
        yOutput.format(initialPosition.y) + ", " +
        zOutput.format(initialPosition.z) + ", " +
        a + ", " +
        b + ", " +
        c + ",0;"
      );
    } else {
      if (!retracted) {
        writeBlock(translate("Submacro") + " Retractzmax;");
      }
      writeBlock("Axyzabc 1, " +
        xOutput.format(initialPosition.x) + ", " +
        yOutput.format(initialPosition.y) + ", " +
        "z6p" + ", " +
        a + ", " +
        b + ", " +
        c + ";"
      );
      writeBlock("Axyzabc 1, " +
        xOutput.format(initialPosition.x) + ", " +
        yOutput.format(initialPosition.y) + ", " +
        zOutput.format(initialPosition.z) + ", " +
        a + ", " +
        b + ", " +
        c + ";"
      );
    }
    // writeBlock(gMotionModal.format(1), xOutput.format(initialPosition.x) + ", " + yOutput.format(initialPosition.y) + ", " + "z6p"  + ", 0,0;");
    // writeBlock(gMotionModal.format(1), xOutput.format(initialPosition.x) + ", " + yOutput.format(initialPosition.y) + ", " + zOutput.format(initialPosition.z) + ",0,0;");
  } else {
    writeBlock(gMotionModal.format(1), xOutput.format(initialPosition.x) + ", " + yOutput.format(initialPosition.y) + ", " + "z6p"  + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(initialPosition.x) + ", " + yOutput.format(initialPosition.y) + ", " + zOutput.format(initialPosition.z) + ", 0, 0;");
  }

  if (properties.useParametricFeed /*&&
      hasParameter("operation-strategy") &&
      (getParameter("operation-strategy") != "drill")*/ &&
      !(currentSection.hasAnyCycle && currentSection.hasAnyCycle())) {
    if (!insertToolCall &&
        activeMovements &&
        (getCurrentSectionId() > 0) &&
        ((getPreviousSection().getPatternId() == currentSection.getPatternId()) && (currentSection.getPatternId() != 0))) {
      // use the current feeds
    } else {
      initializeActiveFeeds(currentSection);
    }
  } else {
    activeMovements = undefined;
  }
}

function onDwell(seconds) {
  writeln(localize("Dwell") + " " + secFormat.format(seconds) + ", 0, 0, 0, 0, 0, 0;");
}

function onSpindleSpeed(spindleSpeed) {
  writeBlock(translate("Rpm") + " 3, " + rpmFormat.format(spindleSpeed) + ", 0, 30;");
}

function onCycle() {
}

/** Convert approach to sign. */
function approach(value) {
  validate((value == "positive") || (value == "negative"), "Invalid approach.");
  return (value == "positive") ? 1 : -1;
}

function onCyclePoint(x, y, z) {
  writeBlock(getFeed(cycle.feedrate));

  if (isProbeOperation(currentSection)) {
    forceXYZ();
  }

  switch (cycleType) {
  case "bore-milling":
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.clearance) + ",0,0;");
    mcrBoreMilling(cycle);
    break;
  case "thread-milling":
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.clearance) + ",0,0;");
    mcrThreadMilling(cycle);
    break;
  case "probing-x":
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    var touchPositionX1 = x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    writeBlock("Xvalue1 = " + touchPositionX1 + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = X6p + (" + xOutput.format(x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2)) + ") - Xvalue1;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");
    break;
  case "probing-y":
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    var touchPositionY1 = y + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    writeBlock("Yvalue1 = " + touchPositionY1 + ";");
    writeBlock("Taxyz 2, X6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock("Newpos = Y6p + (" + yOutput.format(y + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2)) + ") - Yvalue1;");
    writeBlock(translate("Setzp") + " X6p, Newpos, Z6p;");
    break;
  case "probing-z":
    var zpos = zOutput.format(Math.min(z - cycle.depth + cycle.probeClearance, cycle.retract));
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zpos + ", 0, 0;");
    writeBlock(translate("Zheight") + " 0, 0, 1, 0, " + zpos + ", " + zpos + ";");
    break;
  case "probing-x-wall":
    var touchPositionX1 = x + cycle.width1 / 2 + (tool.diameter / 2 - cycle.probeOvertravel);
    var touchPositionX2 = x - cycle.width1 / 2 - (tool.diameter / 2 - cycle.probeOvertravel);

    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x + cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x + cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Xvalue1 = " + xyzFormat.format(touchPositionX1) + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x - cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x - cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Xvalue2 = " + xyzFormat.format(touchPositionX2) + ";");
    writeBlock("Taxyz 2, Xvalue2, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = x6p + " + xOutput.format(x) + " - (Xvalue1 + Xvalue2) / 2;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-y-wall":
    var touchPositionY1 = y + cycle.width1 / 2 + (tool.diameter / 2 - cycle.probeOvertravel);
    var touchPositionY2 = y - cycle.width1 / 2 - (tool.diameter / 2 - cycle.probeOvertravel);

    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y + cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y + cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Yvalue1 = " + xyzFormat.format(touchPositionY1) + ";");
    writeBlock("Taxyz 2, X6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y - cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y - cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Yvalue2 = " + xyzFormat.format(touchPositionY2) + ";");
    writeBlock("Taxyz 2, X6p, Yvalue2, Z6p, 1, 0, 0;");
    writeBlock("Newpos = y6p + " + yOutput.format(y) + " - (Yvalue1 + Yvalue2) / 2;");
    writeBlock(translate("Setzp") + " X6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-x-channel":
    var touchPositionX1 = x + (cycle.width1 / 2 + cycle.probeOvertravel);
    var touchPositionX2 = x - (cycle.width1 / 2 + cycle.probeOvertravel);

    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Xvalue1 = " + xyzFormat.format(touchPositionX1) + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Xvalue2 = " + xyzFormat.format(touchPositionX2) + ";");
    writeBlock("Taxyz 2, Xvalue2, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = x6p + " + xOutput.format(x) + " - (Xvalue1 + Xvalue2) / 2;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-x-channel-with-island":
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x + cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x + cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionX1 = xOutput.getCurrent() + cycle.probeClearance + cycle.probeOvertravel;
    writeBlock("Xvalue1 = " + xyzFormat.format(touchPositionX1) + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x - cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x - cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionX2 = xOutput.getCurrent() - cycle.probeClearance - cycle.probeOvertravel;
    writeBlock("Xvalue2 = " + xyzFormat.format(touchPositionX2) + ";");
    writeBlock("Taxyz 2, Xvalue2, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = x6p + " + xOutput.format(x) + " - (Xvalue1 + Xvalue2) / 2;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-y-channel":
    var touchPositionY1 = y + (cycle.width1 / 2 + cycle.probeOvertravel);
    var touchPositionY2 = y - (cycle.width1 / 2 + cycle.probeOvertravel);

    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Yvalue1 = " + xyzFormat.format(touchPositionY1) + ";");
    writeBlock("Taxyz 2, x6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock("Yvalue2 = " + xyzFormat.format(touchPositionY2) + ";");
    writeBlock("Taxyz 2, x6p, Yvalue2, Z6p, 1, 0, 0;");
    writeBlock("Newpos = y6p + " + yOutput.format(y) + " - (Yvalue1 + Yvalue2) / 2;");
    writeBlock(translate("Setzp") + " x6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-y-channel-with-island":
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y + cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y + cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionY1 = yOutput.getCurrent() + cycle.probeClearance + cycle.probeOvertravel;
    writeBlock("Yvalue1 = " + xyzFormat.format(touchPositionY1) + ";");
    writeBlock("Taxyz 2, x6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y - cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y - cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionY2 = yOutput.getCurrent() - cycle.probeClearance - cycle.probeOvertravel;
    writeBlock("Yvalue2 = " + xyzFormat.format(touchPositionY2) + ";");
    writeBlock("Taxyz 2, x6p, Yvalue2, Z6p, 1, 0, 0;");
    writeBlock("Newpos = y6p + " + yOutput.format(y) + " - (Yvalue1 + Yvalue2) / 2;");
    writeBlock(translate("Setzp") + " x6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-xy-circular-boss":
    // X positions
    var touchPositionX1 = x + cycle.width1 / 2 + (tool.diameter / 2 - cycle.probeOvertravel); // this might be wrong
    var touchPositionX2 = x - cycle.width1 / 2 - (tool.diameter / 2 - cycle.probeOvertravel); // this might be wrong

    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x + cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x + cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Xvalue1 = " + xyzFormat.format(touchPositionX1) + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x - cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x - cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Xvalue2 = " + xyzFormat.format(touchPositionX2) + ";");
    writeBlock("Taxyz 2, Xvalue2, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = x6p + " + xOutput.format(x) + " - (Xvalue1 + Xvalue2) / 2;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");

    // Y positions
    forceXYZ();
    var touchPositionY1 = y + cycle.width1 / 2 + (tool.diameter / 2 - cycle.probeOvertravel);
    var touchPositionY2 = y - cycle.width1 / 2 - (tool.diameter / 2 - cycle.probeOvertravel);

    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y + cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y + cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Yvalue1 = " + xyzFormat.format(touchPositionY1) + ";");
    writeBlock("Taxyz 2, X6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y - cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y - cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Yvalue2 = " + xyzFormat.format(touchPositionY2) + ";");
    writeBlock("Taxyz 2, X6p, Yvalue2, Z6p, 1, 0, 0;");
    writeBlock("Newpos = y6p + " + yOutput.format(y) + " - (Yvalue1 + Yvalue2) / 2;");
    writeBlock(translate("Setzp") + " X6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-xy-circular-hole":
    // X positions
    var touchPositionX1 = x + (cycle.width1 / 2 + cycle.probeOvertravel - tool.diameter / 2);
    var touchPositionX2 = x - (cycle.width1 / 2 + cycle.probeOvertravel - tool.diameter / 2);

    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Xvalue1 = " + xyzFormat.format(touchPositionX1) + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Xvalue2 = " + xyzFormat.format(touchPositionX2) + ";");
    writeBlock("Taxyz 2, Xvalue2, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = x6p + " + xOutput.format(x) + " - (Xvalue1 + Xvalue2) / 2;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");

    // Y positions
    forceXYZ();
    var touchPositionY1 = y + (cycle.width1 / 2 + cycle.probeOvertravel - tool.diameter / 2);
    var touchPositionY2 = y - (cycle.width1 / 2 + cycle.probeOvertravel - tool.diameter / 2);

    writeBlock("Yvalue1 = " + xyzFormat.format(touchPositionY1) + ";");
    writeBlock("Taxyz 2, X6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock("Yvalue2 = " + xyzFormat.format(touchPositionY2) + ";");
    writeBlock("Taxyz 2, X6p, Yvalue2, Z6p, 1, 0, 0;");
    writeBlock("Newpos = y6p + " + yOutput.format(y) + " - (Yvalue1 + Yvalue2) / 2;");
    writeBlock(translate("Setzp") + " X6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-xy-circular-hole-with-island":
    // X positions
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x + cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x + cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionX1 = xOutput.getCurrent() + cycle.probeClearance + cycle.probeOvertravel;
    writeBlock("Xvalue1 = " + xyzFormat.format(touchPositionX1) + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x - cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x - cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionX2 = xOutput.getCurrent() - cycle.probeClearance - cycle.probeOvertravel;
    writeBlock("Xvalue2 = " + xyzFormat.format(touchPositionX2) + ";");
    writeBlock("Taxyz 2, Xvalue2, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = x6p + " + xOutput.format(x) + " - (Xvalue1 + Xvalue2) / 2;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");

    // Y positions
    forceXYZ();
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y + cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y + cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionY1 = yOutput.getCurrent() + cycle.probeClearance + cycle.probeOvertravel;
    writeBlock("Yvalue1 = " + xyzFormat.format(touchPositionY1) + ";");
    writeBlock("Taxyz 2, x6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y - cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y - cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionY2 = yOutput.getCurrent() - cycle.probeClearance - cycle.probeOvertravel;
    writeBlock("Yvalue2 = " + xyzFormat.format(touchPositionY2) + ";");
    writeBlock("Taxyz 2, x6p, Yvalue2, Z6p, 1, 0, 0;");
    writeBlock("Newpos = y6p + " + yOutput.format(y) + " - (Yvalue1 + Yvalue2) / 2;");
    writeBlock(translate("Setzp") + " x6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-xy-rectangular-boss":
    // X positions
    var touchPositionX1 = x + cycle.width1 / 2 + (tool.diameter / 2 - cycle.probeOvertravel); // this might be wrong
    var touchPositionX2 = x - cycle.width1 / 2 - (tool.diameter / 2 - cycle.probeOvertravel); // this might be wrong

    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x + cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x + cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Xvalue1 = " + xyzFormat.format(touchPositionX1) + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x - cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x - cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Xvalue2 = " + xyzFormat.format(touchPositionX2) + ";");
    writeBlock("Taxyz 2, Xvalue2, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = x6p + " + xOutput.format(x) + " - (Xvalue1 + Xvalue2) / 2;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");

    // Y positions
    var touchPositionY1 = y + cycle.width2 / 2 + (tool.diameter / 2 - cycle.probeOvertravel);
    var touchPositionY2 = y - cycle.width2 / 2 - (tool.diameter / 2 - cycle.probeOvertravel);

    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y + cycle.width2 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y + cycle.width2 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Yvalue1 = " + xyzFormat.format(touchPositionY1) + ";");
    writeBlock("Taxyz 2, X6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y - cycle.width2 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y - cycle.width2 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Yvalue2 = " + xyzFormat.format(touchPositionY2) + ";");
    writeBlock("Taxyz 2, X6p, Yvalue2, Z6p, 1, 0, 0;");
    writeBlock("Newpos = y6p + " + yOutput.format(y) + " - (Yvalue1 + Yvalue2) / 2;");
    writeBlock(translate("Setzp") + " X6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-xy-rectangular-hole":
    // X positions
    var touchPositionX1 = x + (cycle.width1 / 2 + cycle.probeOvertravel - tool.diameter / 2);
    var touchPositionX2 = x - (cycle.width1 / 2 + cycle.probeOvertravel - tool.diameter / 2);

    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Xvalue1 = " + xyzFormat.format(touchPositionX1) + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Xvalue2 = " + xyzFormat.format(touchPositionX2) + ";");
    writeBlock("Taxyz 2, Xvalue2, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = x6p + " + xOutput.format(x) + " - (Xvalue1 + Xvalue2) / 2;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");

    // Y positions
    forceXYZ();
    var touchPositionY1 = y + (cycle.width2 / 2 + cycle.probeOvertravel - tool.diameter / 2);
    var touchPositionY2 = y - (cycle.width2 / 2 + cycle.probeOvertravel - tool.diameter / 2);

    writeBlock("Yvalue1 = " + xyzFormat.format(touchPositionY1) + ";");
    writeBlock("Taxyz 2, X6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock("Yvalue2 = " + xyzFormat.format(touchPositionY2) + ";");
    writeBlock("Taxyz 2, X6p, Yvalue2, Z6p, 1, 0, 0;");
    writeBlock("Newpos = y6p + " + yOutput.format(y) + " - (Yvalue1 + Yvalue2) / 2;");
    writeBlock(translate("Setzp") + " X6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-xy-rectangular-hole-with-island":
    // X positions
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x + cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x + cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionX1 = xOutput.getCurrent() + cycle.probeClearance + cycle.probeOvertravel;
    writeBlock("Xvalue1 = " + xyzFormat.format(touchPositionX1) + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x - cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x - cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionX2 = xOutput.getCurrent() - cycle.probeClearance - cycle.probeOvertravel;
    writeBlock("Xvalue2 = " + xyzFormat.format(touchPositionX2) + ";");
    writeBlock("Taxyz 2, Xvalue2, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = x6p + " + xOutput.format(x) + " - (Xvalue1 + Xvalue2) / 2;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");

    // Y positions
    forceXYZ();
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y + cycle.width2 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y + cycle.width2 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionY1 = yOutput.getCurrent() + cycle.probeClearance + cycle.probeOvertravel;
    writeBlock("Yvalue1 = " + xyzFormat.format(touchPositionY1) + ";");
    writeBlock("Taxyz 2, x6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y - cycle.width2 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y - cycle.width2 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionY2 = yOutput.getCurrent() - cycle.probeClearance - cycle.probeOvertravel;
    writeBlock("Yvalue2 = " + xyzFormat.format(touchPositionY2) + ";");
    writeBlock("Taxyz 2, x6p, Yvalue2, Z6p, 1, 0, 0;");
    writeBlock("Newpos = y6p + " + yOutput.format(y) + " - (Yvalue1 + Yvalue2) / 2;");
    writeBlock(translate("Setzp") + " x6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-xy-inner-corner":
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionX1 = x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    writeBlock("Xvalue1 = " + touchPositionX1 + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = X6p + (" + xOutput.format(x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2)) + ") - Xvalue1;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");

    // Y position
    forceXYZ();
    var touchPositionY1 = y + approach(cycle.approach2) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    writeBlock("Yvalue1 = " + touchPositionY1 + ";");
    writeBlock("Taxyz 2, X6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock("Newpos = Y6p + (" + yOutput.format(y + approach(cycle.approach2) * (cycle.probeClearance + tool.diameter / 2)) + ") - Yvalue1;");
    writeBlock(translate("Setzp") + " X6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-xy-outer-corner":
    // X position
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y * -1) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    var touchPositionX1 = x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    writeBlock("Xvalue1 = " + touchPositionX1 + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = X6p + (" + xOutput.format(x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2)) + ") - Xvalue1;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");

    // Y position
    forceXYZ();
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x * -1) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    var touchPositionY1 = y + approach(cycle.approach2) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    writeBlock("Yvalue1 = " + touchPositionY1 + ";");
    writeBlock("Taxyz 2, X6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock("Newpos = Y6p + (" + yOutput.format(y + approach(cycle.approach2) * (cycle.probeClearance + tool.diameter / 2)) + ") - Yvalue1;");
    writeBlock(translate("Setzp") + " X6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-x-plane-angle":
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y + cycle.probeSpacing / 2) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y + cycle.probeSpacing / 2) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionX1 = x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    var touchPositionX2 = touchPositionX1;
    writeBlock("Xvalue1 = " + touchPositionX1 + ";");
    writeBlock("Xvalue2 = " + touchPositionX2 + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "x6p" + ", " + "y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y - cycle.probeSpacing / 2) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y - cycle.probeSpacing / 2) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Taxyz 2, Xvalue2, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Rotationvalue = Arctan ( ( Xvalue2 - Xvalue1 ) / " + "(" + (y + cycle.probeSpacing / 2) + "-" + (y - cycle.probeSpacing / 2) + ") );");
    writeBlock(translate("Rotation") + " Rotationvalue, 1, 1, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-y-plane-angle":
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x + cycle.probeSpacing / 2) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x + cycle.probeSpacing / 2) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionY1 = y + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    var touchPositionY2 = touchPositionY1;
    writeBlock("Yvalue1 = " + touchPositionY1 + ";");
    writeBlock("Yvalue2 = " + touchPositionY2 + ";");
    writeBlock("Taxyz 2, X6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "x6p" + ", " + "y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x - cycle.probeSpacing / 2) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x - cycle.probeSpacing / 2) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Taxyz 2, X6p, Yvalue2, Z6p, 1, 0, 0;");
    writeBlock("Rotationvalue = Arctan ( ( Yvalue2 - Yvalue1 ) / " + "(" + (x + cycle.probeSpacing / 2) + "-" + (x - cycle.probeSpacing / 2) + ") );");
    writeBlock(translate("Rotation") + " Rotationvalue, 1, 1, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  default:
    expandCyclePoint(x, y, z);
  }
}

function mcrBoreMilling(cycle) {

  if (cycle.numberOfSteps > 2) {
    error(localize("Only 2 steps are allowed for bore-milling"));
    return;
  }

  var helixCycles = Math.floor(cycle.depth/cycle.pitch); // needs to be tested
  var XYCleaning = (cycle.numberOfSteps == 2) ? cycle.stepover : 0;
  var bottomCleaning = 0;
  var fastZPlunge = cycle.clearance - cycle.retract;
  var slowZPlunge = cycle.retract - cycle.stock;
  var maxZDepthPerStep = tool.fluteLength * 0.8;

  var block = subst(localize("Drill") + " %1, %5, %2, %3, %4, 1, %6, %7, %8;",
    xyzFormat.format(fastZPlunge),
    xyzFormat.format(cycle.diameter),
    helixCycles,
    xyzFormat.format(XYCleaning),
    xyzFormat.format(slowZPlunge),
    bottomCleaning,
    xyzFormat.format(cycle.depth),
    xyzFormat.format(maxZDepthPerStep)
  );

  writeBlock(block);
}

function mcrThreadMilling(cycle) {
  var fastZPlunge = cycle.clearance - cycle.retract;
  var slowZPlunge = cycle.retract - cycle.stock;
  var threadDirection = (cycle.threading == "right") ? 1 : -1;

  var stringSubst = new StringSubstitution();
  stringSubst.setValue("ThreadNorm", 0);
  stringSubst.setValue("ThreadMillingDirection", 0);
  stringSubst.setValue("ThreadDiameter", xyzFormat.format(cycle.diameter * threadDirection));
  stringSubst.setValue("InnerOuter", 1);
  stringSubst.setValue("Pitch", xyzFormat.format(cycle.pitch));
  stringSubst.setValue("HoleDepth", xyzFormat.format(cycle.depth + 1));
  stringSubst.setValue("ThreadDepth", xyzFormat.format(cycle.depth));
  stringSubst.setValue("CleanXY", xyzFormat.format(cycle.repeatPass));
  stringSubst.setValue("FastZMove", xyzFormat.format(fastZPlunge));
  stringSubst.setValue("SlowZMove", xyzFormat.format(slowZPlunge));
  stringSubst.setValue("ThreadMillAngle", 60);
  stringSubst.setValue("Predrill", 0);
  stringSubst.setValue("ThreadID", 0);
  stringSubst.setValue("Sink", 1); // 0 = with sink, 1 = without sink

  writeBlock(
    stringSubst.substitute(translate("Thread") + " ${ThreadNorm}, ${ThreadMillingDirection}, ${ThreadDiameter}, ${InnerOuter}, ${Pitch}, ${HoleDepth}, ${ThreadDepth}, ${CleanXY}, ${FastZMove}, ${SlowZMove}, ${ThreadMillAngle}, ${Predrill}, ${Sink}, ${ThreadID};")
  );
}

// implement G93 command
function mcrSetInverseTimeFeed() {
  directWriteToCNC("G93");
}

// implement G94 command
function mcrSetTimeFeed() {
  directWriteToCNC("G94");
}

//write a command to the cnc kernel without interpretation from the control
function directWriteToCNC(command) {
  error(localize("Inverse Time feed is currently not supported."));
  return;
}

function onCycleEnd() {
  if (!cycleExpanded) {
    zOutput.reset();
  }

  var probeWorkOffsetCode;
  if (isProbeOperation(currentSection)) {
    var workOffset = probeOutputWorkOffset ? probeOutputWorkOffset : currentWorkOffset;
    if (workOffset != 0) {
      if (workOffset >= 19) {
        error(localize("Work offset is out of range."));
        return;
      }
      probeWorkOffsetCode = workOffset;
      writeBlock("Position " + probeWorkOffsetCode + ", 3;");
    }
    forceXYZ();
  }
}

var probeOutputWorkOffset = 1;

function onParameter(name, value) {
  if (name == "probe-output-work-offset") {
    probeOutputWorkOffset = (value > 0) ? value : 1;
  }
}

var pendingRadiusCompensation = -1;

function onRadiusCompensation() {
  pendingRadiusCompensation = radiusCompensation;
}

function onRapid(_x, _y, _z) {
  var xyz = xOutput.format(_x) + ", " + yOutput.format(_y) + ", " + zOutput.format(_z);
  if (xyz) {
    if (pendingRadiusCompensation >= 0) {
      error(localize("Radius compensation mode cannot be changed at rapid traversal."));
      return;
    }
    writeBlock(gMotionModal.format(1), xyz + ", 0, 0;");
    forceFeed();
  }
}

function onLinear(_x, _y, _z, feed) {
  var xyz = xOutput.format(_x) + ", " + yOutput.format(_y) + ", " + zOutput.format(_z);
  var f = getFeed(feed);

  if (f) {
    writeBlock(f);
  }
  if (xyz) {
    if (pendingRadiusCompensation >= 0) {
      pendingRadiusCompensation = -1;
      switch (radiusCompensation) {
      case RADIUS_COMPENSATION_LEFT:
        writeBlock(translate("Tcomp") + " 1," + " 0, 0, 1, 1;");
        writeBlock(gMotionModal.format(0), xyz + ", 0, 0;");
        break;
      case RADIUS_COMPENSATION_RIGHT:
        writeBlock(translate("Tcomp") + " 2," + " 0, 0, 1, 1;");
        writeBlock(gMotionModal.format(0), xyz + ", 0, 0;");
        break;
      default:
        writeBlock(translate("Tcomp") + " 0," + " 0, 0, 1, 1;");
        writeBlock(gMotionModal.format(0), xyz + ", 0, 0;");
      }
    } else {

      //Anpassung an die funktion drehfräsen
      if( properties._MillTurn ){
    
        var targetVec = new Vector(_x,_y,_z);
        var startVec = getCurrentPosition();
        var linearLength = Vector.diff(targetVec, startVec).length;
        var incTurns = linearLength / properties._FeedPerTurn * 360;
        
          var steps = Math.ceil(incTurns / 90);
          for (step = 1;step<=steps ;step++){
            var currX = startVec.x + (targetVec.x - startVec.x) / steps * step;
            var currY = startVec.y + (targetVec.y - startVec.y) / steps * step;
            var currZ = startVec.z + (targetVec.z - startVec.z) / steps * step;
            forceXYZ();
            writeBlock("Cpos = C6P + " + xOutput.format(incTurns/steps));
            writeBlock("Axyzabc 0, " +  xOutput.format(currX) + ", " + yOutput.format(currY) + ", " + zOutput.format(currZ) + ", " + "a6p" + ", " + "0" + ", Cpos" + ";");
          }
                      
      }else{
         writeBlock(gMotionModal.format(0), xyz + ", 0, 0;");
      }
     
    }
  } else if (f) {
    if (getNextRecord().isMotion()) { // try not to output feed without motion
      forceFeed(); // force feed on next line
    } else {
      writeBlock(gMotionModal.format(0), f);
    }
  }
}

function onRapid5D(_x, _y, _z, _a, _b, _c) {
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation mode cannot be changed at rapid traversal."));
    return;
  }

  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var a = (machineConfiguration.isMachineCoordinate(0) ? aOutput.format(_a) : "a6p");
  var b = (machineConfiguration.isMachineCoordinate(1) ? bOutput.format(_b) : "b6p");
  var c = (machineConfiguration.isMachineCoordinate(2) ? cOutput.format(_c) : "c6p");

  if (currentSection.isOptimizedForMachine() && (useRTCP && (properties._got4thAxis && properties._got5thAxis))) {
    // non TCP
    writeBlock(translate("Submacro") + " Transformpath 0, 1, 0, " + x + ", " + y + ", " + z + ", " + a + ", " + b + ", " + c + ", 0;");
  } else {
    forceXYZ();
    writeBlock("Axyzabc 1, " + x + ", " + y + ", " + z + ", " + a + ", " + b + ", " + c + ";");
  }
  forceFeed();
}

var currentFMode;

function onLinear5D(_x, _y, _z, _a, _b, _c, feed) {
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation cannot be activated/deactivated for 5-axis move."));
    return;
  }

  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var a = (machineConfiguration.isMachineCoordinate(0) ? aOutput.format(_a) : "a6p");
  var b = (machineConfiguration.isMachineCoordinate(1) ? bOutput.format(_b) : "b6p");
  var c = (machineConfiguration.isMachineCoordinate(2) ? cOutput.format(_c) : "c6p");

  // get feed rate number
  if (useInverseTimeFeed) {
    var f = {frn:0, fmode:0};
    if (a || b || c) {
      f = getMultiaxisFeed(_x, _y, _z, _a, _b, _c, feed);
    } else {
      f.frn = feedOutput.format(feed);
      f.fmode = 94;
    }
  }
  
  if (x || y || z || a || b || c) {
    if (useRTCP && (properties._got4thAxis && properties._got5thAxis)) {
      if (useInverseTimeFeed) {
        if (currentFMode != f.fmode) {
          directWriteToCNC("G" + f.fmode);
          currentFMode = f.fmode;
        }
      } else {
        writeBlock(getFeed(feed));
      }
      writeBlock(translate("Submacro") + " Transformpath 0, 0, 0, " + x + ", " + y + ", " + z + ", " + a + ", " + b + ", " + c + ", " + (useInverseTimeFeed ? f.frn : 0) + ";");
    } else {
      if (useInverseTimeFeed) {
        if (currentFMode != f.fmode) {
          directWriteToCNC("G" + f.fmode);
          currentFMode = f.fmode;
        }
        writeBlock(translate("Feed") + " " + f.frn + (Array(4).join(", " + f.frn)) + ";");
      } else {
        writeBlock(getFeed(feed));
      }
      writeBlock("Axyzabc 0, " + x + ", " + y + ", " + z + ", " + a + ", " + b + ", " + c + ";");
    }
  } else if (f) {
    if (getNextRecord().isMotion()) { // try not to output feed without motion
      forceFeed(); // force feed on next line
    } else {
      writeBlock(getFeed(feed));
    }
  }
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  var f = getFeed(feed);
  if (isHelical() || (getCircularPlane() != PLANE_XY)) {
    var t = tolerance;
    if (hasParameter("operation:tolerance")) {
      t = getParameter("operation:tolerance");
    }
    linearize(t);
    return;
  }

  var start = getCurrentPosition();
  var startAngle = Math.atan2(start.y - cy, start.x - cx);
  var endAngle = Math.atan2(y - cy, x - cx);

  if (f) {
    writeBlock(f);
  }

  writeln(
    translate("Circle")  + " " +
    xyzFormat.format(2 * getCircularRadius()) + ", " +
    "0, " + // hs
    "0, " + // hl
    (clockwise ? -360 : 0) + ", " +
    angleFormat.format(startAngle) + ", " + // begin angle
    angleFormat.format(endAngle) + ", " + // end angle
    "0, " + // do not connect start/end
    "0, " + // center
    "2, " + // fk
    "1, " + // yf
    xyzFormat.format(getHelicalPitch()) + ";" // zb
  );
}

function translate(text) {
  switch (properties.language) {
  case "en":
    return text;
  case "de":
    switch (text) {
    case "Coolant":
      return "Sprueh";
    case "Condition":
      return "Bedingung";
    case "Submacro":
      return "Submakro";
    case "Dynamics":
      return "Dynamik";
    case "Contour_smoothing":
      return "Konturglaettung";
    case "Label":
      return "Markierung";
    case "Tcomp":
      return "Fkomp";
    case "Message":
      return "Melde";
    case "Feed":
      return "Vorschub";
    case "Rpm":
      return "Drehzahl";
    case "Number of tools in use":
      return "Anzahl der benutzten Werkzeuge";
    case "Tool":
      return "Werkzeug";
    case "Drill":
      return "Bohren";
    case "Circle":
      return "Kreis";
    case "Thread":
      return "Gewinde";
    case "Setzp":
      return "Setrel";
    case "Workpiece dimensions":
      return "Abmessungen Werkstueck";
    case "Zeromem":
      return "Relsp";
    case "Description":
      return "Beschreibung";
    case "Part size":
      return "Groesse";
    case "Zheight":
      return "Zhmess";
    case "Rotation":
      return "Drehung";
    case "\r\n________________________________________" +
         "\r\n|              error                    |" +
         "\r\n|                                       |" +
         "\r\n| 4/5 axis operations detected.         |" +
         "\r\n| You have to enable the property       |" +
         "\r\n| got4thAxis or got5Axis,                |" +
         "\r\n| otherwise you can only post           |" +
         "\r\n| 3 Axis programs.                      |" +
         "\r\n| If you still have issues,             |" +
         "\r\n| please contact www.DATRON.com!        |" +
         "\r\n|_______________________________________|\r\n":
      return "\r\n________________________________________" +
        "\r\n|              Fehler                    |" +
        "\r\n|                                        |" +
        "\r\n| 4/5 Achs Operationen gefunden.         |" +
        "\r\n| Sie muessen die Property               |" +
        "\r\n| got4thAxis bzw. got5thAxis aktivieren, |" +
        "\r\n| andernfalls koennen Sie lediglich      |" +
        "\r\n| 3 Achsen Programme erzeugen.           |" +
        "\r\n| Besteht das Problem weiterhin,         |" +
        "\r\n| wenden Sie sich bitte an www.datron.de |" +
        "\r\n|________________________________________|\r\n";
    }
    break; // end of German
  }
  return text; // use English
}

var currentCoolantMode = COOLANT_OFF;

function setCoolant(coolant) {
  if (!properties.writeCoolantCommands) {
    return; // do not output coolant
  }
  if (coolant == currentCoolantMode) {
    return; // coolant is already active
  }

  if (coolant == COOLANT_OFF) {
    writeBlock(translate("Coolant") + " 4, 0" + ", 2" + ", 0;"); // coolant off
    currentCoolantMode = COOLANT_OFF;
    return;
  }

  var m;
  switch (coolant) {
  case COOLANT_FLOOD:
  case COOLANT_MIST:
    m = 1;
    break;
  case COOLANT_AIR:
    m = 3;
    break;
  default:
    onUnsupportedCoolant(coolant);
    m = 2;
  }
  if (m) {
    writeBlock(translate("Coolant") + " 4, 0" + ", " + m + ", 0;"); // coolant off
    currentCoolantMode = coolant;
  }
}

var mapCommand = {
};

function onCommand(command) {
  switch (command) {
  case COMMAND_COOLANT_OFF:
    setCoolant(COOLANT_OFF);
    return;
  case COMMAND_COOLANT_ON:
    return;
  case COMMAND_STOP:
    return;
  case COMMAND_START_SPINDLE:
    return;
  case COMMAND_LOCK_MULTI_AXIS:
    return;
  case COMMAND_UNLOCK_MULTI_AXIS:
    return;
  case COMMAND_START_CHIP_TRANSPORT:
    return;
  case COMMAND_STOP_CHIP_TRANSPORT:
    return;
  case COMMAND_BREAK_CONTROL:
    return;
  case COMMAND_TOOL_MEASURE:
    return;
  }

  var stringId = getCommandStringId(command);
  var mcode = mapCommand[stringId];
  if (mcode != undefined) {
    writeBlock(mFormat.format(mcode));
  } else {
    onUnsupportedCommand(command);
  }
}

function onSectionEnd() {
  if (currentSection.isMultiAxis() && (currentSection.getOptimizedTCPMode() == 0)) {
    writeBlock("rtcp 0;");
  }
  if (useInverseTimeFeed && currentSection.isMultiAxis()) {
   directWriteToCNC("G" + 94);
   currentFMode = 94;
  }
  if (((getCurrentSectionId() + 1) >= getNumberOfSections()) ||
      (tool.number != getNextSection().getTool().number)) {
    onCommand(COMMAND_BREAK_CONTROL);
  }
  if (isProbeOperation(currentSection)) {
    writeBlock(translate("Rpm") + " 1, 30, 0, 30;");
  }
  if (!isLastSection() && properties.showOperationDialog != "disabled") {
    writeBlock("$Message = \"Start next Operation\";");
    writeBlock(translate("Condition") + " optional_stop, 0, 1, 0, 9999;");
    writeBlock(translate("Message") + " $Message, 0, 0, 0;");
    writeBlock("$Message = \"OK\";");
  }
  writeBlock(") " + formatVariable("Sm_" + formatVariable(getOperationDescription(currentSection))) + ";");
  forceAny();
}

function onClose() {
  writeln("");

  if (properties.writeVersion) {
    if ((typeof getHeaderVersion == "function") && getHeaderVersion()) {
      writeComment(localize("post version") + ": " + getHeaderVersion());
    }
    if ((typeof getHeaderDate == "function") && getHeaderDate()) {
      writeComment(localize("post modified") + ": " + getHeaderDate());
    }
  }

  // dump machine configuration
  var vendor = machineConfiguration.getVendor();
  var model = machineConfiguration.getModel();
  var description = machineConfiguration.getDescription();

  writeComment("Please make sure that the language on your control is set to " + "\"" + properties.language + "\"");
  if (properties.writeMachine && (vendor || model || description)) {
    writeComment(localize("Machine"));
    if (vendor) {
      writeComment("  " + localize("vendor") + ": " + vendor);
    }
    if (model) {
      writeComment("  " + localize("model") + ": " + model);
    }
    if (description) {
      writeComment("  " + localize("description") + ": "  + description);
    }
  }
  writeToolTable();
  writeWorkpiece();

  if (useRTCP && (properties._got4thAxis && properties._got5thAxis)) {
   writeBlock(translate("Submacro") + " Initposition;");
  }

  //write jump to start operation
  if (properties.showOperationDialog == "dropdown") {
    writeBlock(translate("Condition") + " 0, 0, 0 , startOperation, startOperation;");
  }
  
  writeMainProgram();
  writeComment("###############################################");
  // onCommand(COMMAND_COOLANT_OFF);

  if (useRTCP && (properties._got4thAxis && properties._got5thAxis)) {
    writeBlock(translate("Submacro") + " Endmacro;");
  }

  writeBlock(translate("Submacro") + " Retractzmax;");

  setWorkPlane(new Vector(0, 0, 0)); // reset working plane

  if (properties.useParkPosition) {
    writeBlock("Park;");
  } else {
    writeBlock(translate("Submacro") + " Retractzmax;");
    zOutput.reset();
  }
}
