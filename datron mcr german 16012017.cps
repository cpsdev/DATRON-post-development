/**
  Copyright (C) 2012-2016 by Autodesk, Inc.
  All rights reserved.

  DATRON post processor configuration.

  $Revision: 41267 d0013963577a6a8556969c56a8f1d8b0842905a4 $
  $Date: 2017-01-06 16:12:55 $

  FORKID {1FDF0D08-45B6-4EAD-A71D-7BA04089886D}
*/

description = "Generic DATRON MCR (German)";
vendor = "DATRON";
vendorUrl = "http://www.datron.com";
legal = "Copyright (C) 2012-2016 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 24000;

extension = "mcr";
setCodePage("ascii");

longDescription = "Generic post for DATRON CNCs. This post works with all the common Datron CNCs like DATRON C5, DATRON M7, DATRON M75, DATRON M10, DATRON M8Cube, and DATRON MLCube.";

capabilities = CAPABILITY_MILLING;
tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(120);
allowHelicalMoves = false;
allowedCircularPlanes = (1 << PLANE_XY); // allow XY plane only

// user-defined properties
properties = {
  writeMachine: true, // write machine
  writeVersion: false, // include version info
  optionalStop: true, // optional stop
  useParametricFeed: true, // specifies that feed should be output using Q values
  showNotes: false, // specifies that operation notes should be output
  useSmoothing: true, // specifies if smoothing should be used or not
  useDynamic: true, // specifies using dynamic mode or not
  useParkPosition: true, // specifies to use park position at the end of the program
  useTimeStamp: false // specifies to output time stamp
};

var mFormat = createFormat({prefix:"M", width:2, zeropad:true, decimals:1});

var xyzFormat = createFormat({decimals:(unit == MM ? 5 : 5), forceDecimal:false});
var angleFormat = createFormat({decimals:5, scale:DEG});
var abcFormat = createFormat({decimals:5, scale:DEG});
var feedFormat = createFormat({decimals:(unit == MM ? 2 : 2), scale:(unit == MM ? 0.001 : 1)});
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
var language = "de"; // supported languages are: "en", "de"
var maxMaskLength = 40;
var useRTCPSimu = false; // BETA, use TCP "light" or not

// collected state
var currentWorkOffset;
var currentFeedValue = -1;
var optionalSection = false;
var forceSpindleSpeed = false;
var activeMovements; // do not use by default
var currentFeedId;

// format date + time
var timeFormat = createFormat({decimals:0, force:true, width:2, zeropad:true});
var now = new Date();
var nowDay = now.getDate();
var nowMonth = now.getMonth() + 1;
var nowHour = now.getHours();
var nowMin = now.getMinutes();
var nowSec = now.getSeconds();

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

  if (false) { // note: setup your machine here
    var aAxis = createAxis({coordinate:0, table:true, axis:[-1, 0, 0], range:[-102.5, 0], preference:-1});
    var cAxis = createAxis({coordinate:2, table:true, axis:[0, 0, -1], range:[-360, 360], cyclic:true, preference:0});
    machineConfiguration = new MachineConfiguration(aAxis, cAxis);

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

  writeln("!Please make sure that the language on your control is set to " + "\"" + language + "\"" + "!");
  switch (language) {
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

  variablesDeclaration.push("optional_stop");
  variablesDeclaration.push("$Message");
  if (getNumberOfSections() >= maxMaskLength) {
    submacrosDeclaration.push("Initvariables");
  }

  dialogsDeclaration.push("_maske _haupt, " + "1000" + ", 0, " + "\"" + translate("Submacro") + " " + translate("Description") + "\"");
  if (properties.optionalStop) {
    dialogsDeclaration.push("_feld optional_stop, 1, 0, 1, 0, 1, 2, 1," + " \"" + "optional_stop" + "\"" + "," + " \"" + "optional_stop" + "\"");
  }

  //write variables declaration
  var tools = getToolTable();
  for (var i = 0; i < tools.getNumberOfTools(); ++i) {
    var tool = tools.getTool(i);
    variablesDeclaration.push("T" + tool.number);
  }

  var numberOfSections = getNumberOfSections();
  for (var i = 0; i < numberOfSections; ++i) {
    var section = getSection(i);
    variablesDeclaration.push("Op_" + formatVariable(getOperationDescription(section)));
    submacrosDeclaration.push("Sm_" + formatVariable(getOperationDescription(section)));
    if (getNumberOfSections() < maxMaskLength) {
      dialogsDeclaration.push("_feld Op_" + formatVariable(getOperationDescription(section)) + ", 1, 0, 1, 0, 1, 2, 1," + " \"" +
        formatVariable(getOperationDescription(section)) + "\"" + "," + " \"" +
        formatVariable(getOperationDescription(section)) + "\""
      );
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

  if (!is3D()) {
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

    submacrosDeclaration.push("Initposition");
    submacrosDeclaration.push("Endmacro");
  }

  if (useRTCPSimu) {
    submacrosDeclaration.push("Transformpath");
  }
  if (!is3D()) {
    submacrosDeclaration.push("Transformoffset");
  }

  submacrosDeclaration.push("Retractzmax");
  variablesDeclaration.push("Curr_zpno");
  variablesDeclaration.push("Zpos");
  variablesDeclaration.push("Xvalue");
  variablesDeclaration.push("Yvalue");
  variablesDeclaration.push("Zvalue");
  variablesDeclaration.push("Newpos");

  writeBlock("Variable " + variablesDeclaration.join(", ") + ";");
  writeln("");
  writeBlock("Smakros " + submacrosDeclaration.join(", ") + ";");
  writeln("");
  writeBlock(dialogsDeclaration.join(EOL) + ";");
  writeln("");

  if (!is3D()) {
    writeBlock("_exit Endmacro;");
    writeln("");
  }

  if (!is3D()) {
    writeBlock("_maske Transformoffset, 4, 0, \"create a new coordinate system with the given rotation values\"");
    writeBlock("_feld A, 4, 8, 0, -120, 120, 0, 1, \"alpha\", \"rotation around x axis\"");
    writeBlock("_feld B, 4, 8, 0, -120, 120, 0, 1, \"beta\", \"rotation around Y\"");
    writeBlock("_feld C, 4, 8, 0, -9999, 9999, 0, 1, \"gamma\", \"rotation around Z\";");
    writeln("");
  }
  if (useRTCPSimu) {
    writeBlock("_maske Transformpath, 8, 0, \"create a new coordinate system with the given rotation values\"");
    writeBlock("_feld Israpid, 4, 5, 0, -9999, 9999, 2, 0, \"Is rapid\", \"is rapid\"");
    writeBlock("_feld Isinitialposition, 4, 3, 0, -9999, 9999, 2, 1, \"Isinitialposition\", \"If set machine positioning with z max height\"");
    writeBlock("_feld X, 4, 5, 0, -9999, 9999, 0, 1, \"X Value\", \"X Position\"");
    writeBlock("_feld Y, 4, 5, 0, -9999, 9999, 0, 1, \"Y Value\", \"Y Position\"");
    writeBlock("_feld Z, 4, 5, 0, -9999, 9999, 0, 1, \"Z Value\", \"Z Position\"");
    writeBlock("_feld A, 4, 8, 0, -120, 120, 0, 1, \"alpha\", \"rotation around x axis\"");
    writeBlock("_feld B, 4, 8, 0, -120, 120, 0, 1, \"beta\", \"rotation around Y\"");
    writeBlock("_feld C, 4, 8, 0, -9999, 9999, 0, 1, \"gamma\", \"rotation around Z\";");
    writeln("");
  }

  if (numberOfSections >= maxMaskLength) {
    writeBlock("(");
    for (var i = 0; i < numberOfSections; ++i) {
      var section = getSection(i);
      writeBlock("Op_" + formatVariable(getOperationDescription(section)) + " = 1");
    }
    writeln(") Initvariables;");
  }

  if (!is3D()) {
    createPositionInitSubmacro();
    createEndmacro();
  }

  if (!is3D()) {
    createRtcpTransformationSubmacro();
  }

  if (useRTCPSimu) {
    createRtcpSimuSubmacro();
  }

  createRetractMacro();
}

function writeMainProgram() {

  var numberOfSections = getNumberOfSections();
  if (numberOfSections >= maxMaskLength) {
    writeBlock(translate("Submacro") + " Initvariables;");
  }

  for (var i = 0; i < numberOfSections; ++i) {
    var section = getSection(i);
    var Description = getOperationDescription(section);
    var sectionID = i+1;

    var sectionName = formatVariable("Sm_" + Description);
    var maskName = formatVariable("Op_" + Description);

    writeComment("##########" + Description + "##########");
    writeBlock(translate("Condition") + " " + maskName + ", 0, 1, 0, " + sectionID + ";");

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
    var workOffset;
    if (!is3D()) {
      workOffset = 19;
      if (workOffset != currentWorkOffset) {
        writeBlock("Position " + workOffset + ", 2;");
        currentWorkOffset = workOffset;
      }
    } else {
      workOffset = section.workOffset;
      if (workOffset != 0 && workOffset < 41) {
        if (workOffset != currentWorkOffset) {
          writeBlock("Position " + workOffset + ", 2;");
          currentWorkOffset = workOffset;
        }
      }
    }

    writeBlock(translate("Submacro") + " " + sectionName + ";");
    writeBlock(translate("Label") + " " + sectionID + ";");
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
  this.feed = feed;
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
  if (!is3D()) {
    writeBlock("A_temp = " + (machineConfiguration.isMachineCoordinate(0) ? abcFormat.format(abc.x) : "a6p") + " - A_delta;");
    writeBlock("B_temp = " + (machineConfiguration.isMachineCoordinate(1) ? abcFormat.format(abc.y) : "b6p") + " - B_delta;");
    writeBlock("C_temp = " + (machineConfiguration.isMachineCoordinate(2) ? abcFormat.format(abc.z) : "c6p") + " - C_delta;");
    writeBlock("Axyzabc 1, x6p, y6p, z6p, A_temp, B_temp, C_temp;");
  }

  if (!is3D() && !currentSection.isMultiAxis()) {
    writeBlock(translate("Submacro") + " Transformoffset 0, ",
    abcFormat.format(abc.x) +", ",
    abcFormat.format(abc.y) +", ",
    abcFormat.format(abc.z) +";");
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
  error(localize("RTCP is not supported."));
  return;

/*
  writeBlock("(");
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
  writeBlock("X_new = X - X_trans;");
  writeBlock("Y_new = Y - Y_trans;");
  writeBlock("Z_new = ( ( Isinitialposition + 1 ) % 2 ) * ( Z - Z_trans ) + Isinitialposition * Z6max;");

  writeBlock("A_temp =  A - A_delta;");
  writeBlock("B_temp = B - B_delta;");
  writeBlock("C_temp = C - C_delta;");

  writeBlock("Axyzabc Israpid, X_new, Y_new, Z_new, A_temp, B_temp, C_temp;");
  writeBlock(") Transformpath;");
*/
}

function createRtcpTransformationSubmacro() {
  writeBlock("(");
  writeBlock("Position 19, 2;");
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
  writeBlock("Zpos = - Wzl - 10;");
  writeBlock("Axyz 1, Xp, Yp, Zpos, 0, 0;");
  writeBlock(translate("Zeromem") + " Curr_zpno;");
  writeBlock(") Retractzmax;");
}


function createEndmacro() {
  writeBlock("(");
  writeBlock(translate("Submacro") + " Transformoffset 0, 0, 0, 0;");
  writeBlock(") Endmacro;");
}

function isProbeOperation(section) {
  return (section.hasParameter("operation-strategy") && section.getParameter("operation-strategy") == "probe");
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
    !isSameDirection(getPreviousSection().getGlobalFinalToolAxis(), currentSection.getGlobalInitialToolAxis());

  writeBlock("(");
  if (isProbeOperation(currentSection)) {
    writeBlock("T3d 9, 0, 1, 15, 17, 10, 10, 10, 10, 10, 10, 0;")	// Messtaster aktivieren     
    writeBlock("Drehzahl 0, 30, 0, 30;");    
  } else {
    writeBlock("T3d 0, 0, 1, 15, 17, 10, 10, 10, 10, 10, 10, 0;")	// Messtaster deaktivieren       
  }

  if (insertToolCall || newWorkOffset || newWorkPlane) {

    // retract to safe plane
    retracted = true;
    writeBlock(translate("Submacro") + " Retractzmax;");
    forceXYZ();
  }

  if (insertToolCall) {
    forceWorkPlane();
    retracted = true;

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
    if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
      //error(localize("Tool orientation is not supported."));
      error(translate(
        "\r\n________________________________________" +
        "\r\n|              error                    |"+
        "\r\n|                                       |"+
        "\r\n| 5 axis operations require adjustments |"+
        "\r\n| to the postprocessor for your         |"+
        "\r\n| machining system.                     |"+
        "\r\n| Please contact www.DATRON.com!        |"+
        "\r\n|_______________________________________|\r\n"));
      return;
    }
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

    if (useRTCPSimu) {
      writeBlock("Position 19, 2;");
      writeBlock(translate("Submacro") + " Retractzmax;");
      writeBlock(translate("Submacro") + " Transformpath 0, 1, 1, " +
        xOutput.format(initialPosition.x) + ", " +
        yOutput.format(initialPosition.y) + ", " +
        "z6p" + ", " +
        a + ", " +
        b + ", " +
        c + ";"
      );
      writeBlock(translate("Submacro") + " Transformpath 0, 1, 0, " +
        xOutput.format(initialPosition.x) + ", " +
        yOutput.format(initialPosition.y) + ", " +
        zOutput.format(initialPosition.z) + ", " +
        a + ", " +
        b + ", " +
        c + ";"
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
        (getPreviousSection().getPatternId() == currentSection.getPatternId())) {
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
      forceXYZ();
			writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
			writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
			var xValue = x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter/2 + cycle.probeOvertravel);
			writeBlock("Xvalue = " + xValue + ";");
			writeBlock("Taxyz 2, Xvalue, Y6p, Z6p, 1, 0, 0;")
			writeBlock("Newpos = X6p + (" +  xOutput.format(x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter/2)) + ") - Xvalue;");
			writeBlock("Setrel Newpos, Y6p, Z6p;");
      break;
    case "probing-y":
      forceXYZ();
			writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
			writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
			var yValue = y + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter/2 + cycle.probeOvertravel);
			writeBlock("Yvalue = " + yValue + ";");
			writeBlock("Taxyz 2, X6p, Yvalue, Z6p, 1, 0, 0;")
			writeBlock("Newpos = Y6p + (" +  yOutput.format(y + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter/2)) + ") - Yvalue;");
			writeBlock("Setrel X6p, Newpos, Z6p;");
      break;
    case "probing-z":
      forceXYZ();    
      // writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
      var zpos = zOutput.format(Math.min(z - cycle.depth + cycle.probeClearance, cycle.retract));
			writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zpos + ", 0, 0;");
			writeBlock("Zhmess 0, 0, 1, 0, " + zpos + ", " + zpos + ";")
      break;
		/*
    Rest kann alles über T3D messung realisiert werden, Rotation gibt nochmal Spezioool
    Insel wird nicht unterstützt
    case "probing-x-wall":
      writeBlock(gFormat.format(65), "P" + 9810, zOutput.format(z), getFeed(F)); // protected positioning move
      writeBlock(
        gFormat.format(65), "P" + 9812,
        "X" + xyzFormat.format(cycle.width1),
        zOutput.format(z - cycle.depth),
        "Q" + xyzFormat.format(cycle.probeOvertravel),
        "R" + xyzFormat.format(cycle.probeClearance),
        "S" + probeWorkOffsetCode // "T" + toolFormat.format(probeToolDiameterOffset)
      );
      break;
    case "probing-y-wall":
      writeBlock(gFormat.format(65), "P" + 9810, zOutput.format(z), getFeed(F)); // protected positioning move
      writeBlock(
        gFormat.format(65), "P" + 9812,
        "Y" + xyzFormat.format(cycle.width1),
        zOutput.format(z - cycle.depth),
        "Q" + xyzFormat.format(cycle.probeOvertravel),
        "R" + xyzFormat.format(cycle.probeClearance),
        "S" + probeWorkOffsetCode // "T" + toolFormat.format(probeToolDiameterOffset)
      );
      break;
    case "probing-x-channel":
      writeBlock(gFormat.format(65), "P" + 9810, zOutput.format(z - cycle.depth), getFeed(F)); // protected positioning move
      writeBlock(
        gFormat.format(65), "P" + 9812,
        "X" + xyzFormat.format(cycle.width1),
        "Q" + xyzFormat.format(cycle.probeOvertravel),
        // not required "R" + xyzFormat.format(cycle.probeClearance),
        "S" + probeWorkOffsetCode // "T" + toolFormat.format(probeToolDiameterOffset)
      );
      break;
    case "probing-x-channel-with-island":
      writeBlock(gFormat.format(65), "P" + 9810, zOutput.format(z), getFeed(F)); // protected positioning move
      writeBlock(
        gFormat.format(65), "P" + 9812,
        "X" + xyzFormat.format(cycle.width1),
        zOutput.format(z - cycle.depth),
        "Q" + xyzFormat.format(cycle.probeOvertravel),
        "R" + xyzFormat.format(-cycle.probeClearance),
        "S" + probeWorkOffsetCode
      );
      break;
    case "probing-y-channel":
      yOutput.reset();
      writeBlock(gFormat.format(65), "P" + 9810, zOutput.format(z - cycle.depth), getFeed(F)); // protected positioning move
      writeBlock(
        gFormat.format(65), "P" + 9812,
        "Y" + xyzFormat.format(cycle.width1),
        "Q" + xyzFormat.format(cycle.probeOvertravel),
        // not required "R" + xyzFormat.format(cycle.probeClearance),
        "S" + probeWorkOffsetCode
      );
      break;
    case "probing-y-channel-with-island":
      yOutput.reset();
      writeBlock(gFormat.format(65), "P" + 9810, zOutput.format(z), getFeed(F)); // protected positioning move
      writeBlock(
        gFormat.format(65), "P" + 9812,
        "Y" + xyzFormat.format(cycle.width1),
        zOutput.format(z - cycle.depth),
        "Q" + xyzFormat.format(cycle.probeOvertravel),
        "R" + xyzFormat.format(-cycle.probeClearance),
        "S" + probeWorkOffsetCode
      );
      break;
    case "probing-xy-circular-boss":
      writeBlock(gFormat.format(65), "P" + 9810, zOutput.format(z), getFeed(F)); // protected positioning move
      writeBlock(
        gFormat.format(65), "P" + 9814,
        "D" + xyzFormat.format(cycle.width1),
        "Z" + xyzFormat.format(z - cycle.depth),
        "Q" + xyzFormat.format(cycle.probeOvertravel),
        "R" + xyzFormat.format(cycle.probeClearance),
        "S" + probeWorkOffsetCode
      );
      break;
    case "probing-xy-circular-hole":
      writeBlock(gFormat.format(65), "P" + 9810, zOutput.format(z - cycle.depth), getFeed(F)); // protected positioning move
      writeBlock(
        gFormat.format(65), "P" + 9814,
        "D" + xyzFormat.format(cycle.width1),
        "Q" + xyzFormat.format(cycle.probeOvertravel),
        // not required "R" + xyzFormat.format(cycle.probeClearance),
        "S" + probeWorkOffsetCode
      );
      break;
    case "probing-xy-circular-hole-with-island":
      writeBlock(gFormat.format(65), "P" + 9810, zOutput.format(z), getFeed(F)); // protected positioning move
      writeBlock(
        gFormat.format(65), "P" + 9814,
        "Z" + xyzFormat.format(z - cycle.depth),
        "D" + xyzFormat.format(cycle.width1),
        "Q" + xyzFormat.format(cycle.probeOvertravel),
        "R" + xyzFormat.format(-cycle.probeClearance),
        "S" + probeWorkOffsetCode
      );
      break;
    case "probing-xy-rectangular-hole":
      writeBlock(gFormat.format(65), "P" + 9810, zOutput.format(z - cycle.depth), getFeed(F)); // protected positioning move
      writeBlock(
        gFormat.format(65), "P" + 9812,
        "X" + xyzFormat.format(cycle.width1),
        "Q" + xyzFormat.format(cycle.probeOvertravel),
        // not required "R" + xyzFormat.format(-cycle.probeClearance),
        "S" + probeWorkOffsetCode
      );
      writeBlock(
        gFormat.format(65), "P" + 9812,
        "Y" + xyzFormat.format(cycle.width2),
        "Q" + xyzFormat.format(cycle.probeOvertravel),
        // not required "R" + xyzFormat.format(-cycle.probeClearance),
        "S" + probeWorkOffsetCode
      );
      break;
    case "probing-xy-rectangular-boss":
      writeBlock(gFormat.format(65), "P" + 9810, zOutput.format(z), getFeed(F)); // protected positioning move
      writeBlock(
        gFormat.format(65), "P" + 9812,
        "Z" + xyzFormat.format(z - cycle.depth),
        "X" + xyzFormat.format(cycle.width1),
        "R" + xyzFormat.format(cycle.probeClearance),
        "Q" + xyzFormat.format(cycle.probeOvertravel),
        "S" + probeWorkOffsetCode
      );
      writeBlock(
        gFormat.format(65), "P" + 9812,
        "Z" + xyzFormat.format(z - cycle.depth),
        "Y" + xyzFormat.format(cycle.width2),
        "R" + xyzFormat.format(cycle.probeClearance),
        "Q" + xyzFormat.format(cycle.probeOvertravel),
        "S" + probeWorkOffsetCode
      );
      break;
    case "probing-xy-rectangular-hole-with-island":
      writeBlock(gFormat.format(65), "P" + 9810, zOutput.format(z), getFeed(F)); // protected positioning move
      writeBlock(
        gFormat.format(65), "P" + 9812,
        "Z" + xyzFormat.format(z - cycle.depth),
        "X" + xyzFormat.format(cycle.width1),
        "Q" + xyzFormat.format(cycle.probeOvertravel),
        "R" + xyzFormat.format(-cycle.probeClearance),
        "S" + probeWorkOffsetCode
      );
      writeBlock(
        gFormat.format(65), "P" + 9812,
        "Z" + xyzFormat.format(z - cycle.depth),
        "Y" + xyzFormat.format(cycle.width2),
        "Q" + xyzFormat.format(cycle.probeOvertravel),
        "R" + xyzFormat.format(-cycle.probeClearance),
        "S" + probeWorkOffsetCode
      );
      break;

    case "probing-xy-inner-corner":
      var cornerX = x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter/2);
      var cornerY = y + approach(cycle.approach2) * (cycle.probeClearance + tool.diameter/2);
      var cornerI = 0;
      var cornerJ = 0;
      if (cycle.probeSpacing && (cycle.probeSpacing != 0)) {
        cornerI = cycle.probeSpacing;
        cornerJ = cycle.probeSpacing;
      }
      if ((cornerI != 0) && (cornerJ != 0)) {
        g68RotationMode = 2;
      }
      writeBlock(gFormat.format(65), "P" + 9810, zOutput.format(z - cycle.depth), getFeed(F)); // protected positioning move
      writeBlock(
        gFormat.format(65), "P" + 9815, xOutput.format(cornerX), yOutput.format(cornerY),
        conditional(cornerI != 0, "I" + xyzFormat.format(cornerI)),
        conditional(cornerJ != 0, "J" + xyzFormat.format(cornerJ)),
        "Q" + xyzFormat.format(cycle.probeOvertravel),
        conditional((g68RotationMode == 0) || (angularProbingMode == ANGLE_PROBE_USE_CAXIS), "S" + probeWorkOffsetCode)
      );
      break;
    case "probing-xy-outer-corner":
      // writeBlock("Rapid Z=" + xyzFormat.format(cycle.stock));
			// writeBlock("Feed=" +  feedString);
      // writeBlock("Line Z=" + xyzFormat.format(z - cycle.depth + tool.cornerRadius));
      // var measureString = "CornerMeasure "
      // cycle.approach1 == "positive" ?	measureString += "XPositive" : measureString += "XNegative";
			// measureString += " originShift=" + xyzFormat.format(-1 * (x + approach(cycle.approach1) * startPositionOffset));
      // measureString += " searchDistance=" + xyzFormat.format(cycle.probeClearance);



      // var cornerX = x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter/2);
      // var cornerY = y + approach(cycle.approach2) * (cycle.probeClearance + tool.diameter/2);
      // var cornerI = 0;
      // var cornerJ = 0;
      // if (cycle.probeSpacing && (cycle.probeSpacing != 0)) {
        // cornerI = cycle.probeSpacing;
        // cornerJ = cycle.probeSpacing;
      // }
      // if ((cornerI != 0) && (cornerJ != 0)) {
        // g68RotationMode = 2;
      // }
      // writeBlock(gFormat.format(65), "P" + 9810, zOutput.format(z - cycle.depth), getFeed(F)); // protected positioning move
      // writeBlock(
        // gFormat.format(65), "P" + 9816, xOutput.format(cornerX), yOutput.format(cornerY),
        // conditional(cornerI != 0, "I" + xyzFormat.format(cornerI)),
        // conditional(cornerJ != 0, "J" + xyzFormat.format(cornerJ)),
        // "Q" + xyzFormat.format(cycle.probeOvertravel),
        // conditional((g68RotationMode == 0) || (angularProbingMode == ANGLE_PROBE_USE_CAXIS), "S" + probeWorkOffsetCode)
      // );
      break;
    case "probing-x-plane-angle":
      forceXYZ();
      writeBlock(gFormat.format(65), "P" + 9810, zOutput.format(z - cycle.depth), getFeed(F)); // protected positioning move
      writeBlock(
        gFormat.format(65), "P" + 9843,
        "X" + xyzFormat.format(x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter/2)),
        "D" + xyzFormat.format(cycle.probeSpacing),
        "Q" + xyzFormat.format(cycle.probeOvertravel)
      );
      g68RotationMode = 1;
      break;
    case "probing-y-plane-angle":
      forceXYZ();

      writeBlock(gFormat.format(65), "P" + 9810, zOutput.format(z - cycle.depth), getFeed(F)); // protected positioning move
      writeBlock(
        gFormat.format(65), "P" + 9843,
        "Y" + xyzFormat.format(y + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter/2)),
        "D" + xyzFormat.format(cycle.probeSpacing),
        "Q" + xyzFormat.format(cycle.probeOvertravel)
      );
      g68RotationMode = 1;
      break;
*/
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
  stringSubst.setValue("CleanXY", 0);
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

function onCycleEnd() {
  if (!cycleExpanded) {
    zOutput.reset();
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
      writeBlock(gMotionModal.format(0), xyz + ", 0, 0;");
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

  if (currentSection.isOptimizedForMachine() && useRTCPSimu) {
    // non TCP
    writeBlock(translate("Submacro") + " Transformpath 0, 1, 0, " + x + ", " + y + ", " + z + ", " + a + ", " + b + ", " + c + ";");
  } else {
    forceXYZ();
    writeBlock("Axyzabc 1, " + x + ", " + y + ", " + z + ", " + a + ", " + b + ", " + c + ";");
  }
  forceFeed();
}

function onLinear5D(_x, _y, _z, _a, _b, _c, feed) {
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation cannot be activated/deactivated for 5-axis move."));
    return;
  }

  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var a = (machineConfiguration.isMachineCoordinate(0) ? aOutput.format(_a) : "a6p");
  var b = (machineConfiguration.isMachineCoordinate(1) ? aOutput.format(_b) : "b6p");
  var c = (machineConfiguration.isMachineCoordinate(2) ? aOutput.format(_c) : "c6p");

  writeBlock(getFeed(feed));
  if (x || y || z || a || b || c) {
    if (useRTCPSimu) {
      writeBlock(translate("Submacro") + " Transformpath 0, 0, 0, " + x + ", " + y + ", " + z + ", " + a + ", " + b + ", " + c + ";");
    } else {
      writeBlock("Axyzabc 0, " + x + ", " + y + ", " + z + ", " + a + ", " + b + ", " + c + ";");
    }
  } else if (f) {
    if (getNextRecord().isMotion()) { // try not to output feed without motion
      forceFeed(); // force feed on next line
    } else {
      writeBlock(gMotionModal.format(0), f);
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
  switch (language) {
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
    case "\r\n________________________________________" +
         "\r\n|              error                    |" +
         "\r\n|                                       |" +
         "\r\n| 5 axis operations require adjustments |" +
         "\r\n| to the postprocessor for your         |" +
         "\r\n| machining system.                     |" +
         "\r\n| Please contact www.DATRON.com!        |" +
         "\r\n|_______________________________________|\r\n":
      return "\r\n________________________________________" +
        "\r\n|              Fehler                    |" +
        "\r\n|                                        |" +
        "\r\n| 5 Achs Operationen erfordern           |" +
        "\r\n| eine Anpassung des Postprozessors      |" +
        "\r\n| auf Ihre Maschine.                     |" +
        "\r\n| Bitte wenden Sie sich an www.datron.de |" +
        "\r\n|________________________________________|\r\n";
    }
    break; // end of German
  }
  return text; // use English
}

var currentCoolantMode = COOLANT_OFF;

function setCoolant(coolant) {
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

  if (((getCurrentSectionId() + 1) >= getNumberOfSections()) ||
      (tool.number != getNextSection().getTool().number)) {
    onCommand(COMMAND_BREAK_CONTROL);
  }
    if (isProbeOperation(currentSection)) {
      writeBlock("Drehzahl 1, 30, 0, 30;");
    }  
  if (!isLastSection() && properties.optionalStop) {
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

  writeComment("Please make sure that the language on your control is set to " + "\"" + language + "\"");
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

  if (!is3D()) {
    writeBlock(translate("Submacro") + " Initposition;");
  }

  writeMainProgram();
  writeComment("###############################################");
  onCommand(COMMAND_COOLANT_OFF);

  if (!is3D()) {
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
