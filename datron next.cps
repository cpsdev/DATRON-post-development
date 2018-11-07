/**
  Copyright (C) 2012-2018 by Autodesk, Inc.
  All rights reserved.

  DATRON post processor configuration.

  $Revision$
  $Date$

  FORKID {21ADEFBF-939E-4D3F-A935-4E61F5958698}
*/

description = "DATRON next";
vendor = "DATRON";
vendorUrl = "http://www.datron.com";
legal = "Copyright (C) 2012-2018 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 24000;

longDescription = "Post for Datron next control. This post is for use with the Datron neo CNC.";

extension = "simpl";
setCodePage("utf-8");

capabilities = CAPABILITY_MILLING;
tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.25, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(120);
allowHelicalMoves = true;
allowedCircularPlanes = (1 << PLANE_XY); // allow XY plane only

// user-defined properties
properties = {
  writeMachine : true, // write machine
  showNotes : false, // specifies that operation notes should be output
  useSmoothing : true, // specifies if smoothing should be used or not
  useDynamic : true, // specifies using dynamic mode or not
  useParkPosition : true, // specifies to use park position at the end of the program
  writeToolTable : true, // write the table with the geometric tool informations
  useSequences : true, // this use a sequence in the output format to perform on large files
  useExternalSequencesFiles : false, // this property create one external sequence files for each operation
  writeCoolantCommands : true, // disable the coolant commands in the file
  useParametricFeed : true, // specifies that feed should be output using parameters
  waitAfterOperation : false, // optional stop
  got4thAxis: false // specifies if the machine has a rotational 4th axis
};

// user-defined property definitions
propertyDefinitions = {
  writeMachine: {title:"Write machine", description:"Output the machine settings in the header of the code.", group:0, type:"boolean"},
  showNotes: {title:"Show notes", description:"Writes operation notes as comments in the outputted code.", type:"boolean"},
  useSmoothing: {title:"Use smoothing", description:"Specifies if smoothing should be used or not.", type:"boolean"},
  useDynamic: {title:"Dynamic mode", description:"Specifies the using of dynamic mode or not.", type:"boolean"},
  useParkPosition: {title: "Park at end of program", description:"Enable to use the park position at end of program.", type:"boolean"},
  writeToolTable: {title:"Write tool table", description:"Write a tool table containing geometric tool information.", group:0, type:"boolean"},
  useSequences: {title:"Use sequences", description:"If enables, sequences are used in the output format on large files.", type:"boolean"},
  useExternalSequencesFiles: {title:"Use external sequence files", description:"If enabled, an external sequence file is created for each operation.", type:"boolean"},
  writeCoolantCommands: {title:"Write coolant commands", description:"Enable/disable coolant code outputs for the entire program.", type:"boolean"},
  useParametricFeed:  {title:"Parametric feed", description:"Specifies the feed value that should be output using a Q value.", type:"boolean"},
  waitAfterOperation: {title:"Wait after operation", description:"If enabled, an optional stop is outputted to pause after each operation.", type:"boolean"},
  got4thAxis: {title:"Has 4th axis", description:"Enable if the machine is equipped with a 4-axis.", type:"boolean"}
};

var gFormat = createFormat({prefix:"G", width:2, zeropad:true, decimals:1});
var mFormat = createFormat({prefix:"M", width:2, zeropad:true, decimals:1});

var xyzFormat = createFormat({decimals:(unit == MM ? 5 : 5), forceDecimal:false});
var abcFormat = createFormat({decimals:5, scale:DEG});
var feedFormat = createFormat({decimals:(unit == MM ? 2 : 2)});
var toolFormat = createFormat({decimals:0});
var dimensionFormat = createFormat({decimals:(unit == MM ? 3 : 5), forceDecimal:false});
var rpmFormat = createFormat({decimals:0, scale:1});
var sleepFormat = createFormat({decimals:0, scale:1000}); // milliseconds
var workpieceFormat = createFormat({decimals:(unit == MM ? 3 : 4), forceSign:true, trim:false});

var toolOutput = createVariable({prefix:"Tool_", force:true}, toolFormat);
var feedOutput = createVariable({prefix:""}, feedFormat);

var xOutput = createVariable({prefix:" X="}, xyzFormat);
var yOutput = createVariable({prefix:" Y="}, xyzFormat);
var zOutput = createVariable({prefix:" Z="}, xyzFormat);
var aOutput = createVariable({prefix:" A="}, abcFormat);
var bOutput = createVariable({prefix:" B="}, abcFormat);
var cOutput = createVariable({prefix:" C="}, abcFormat);

var iOutput = createVariable({prefix:" dX=", force : true}, feedFormat);
var jOutput = createVariable({prefix:" dY=", force : true}, feedFormat);
var kOutput = createVariable({prefix:" dZ="}, feedFormat);

// fixed settings
var useDatronFeedCommand = false; // unsupported for now, keep false
var language = "de"; // specifies the language, replace with getLangId()
var spacingDepth = 0;
var spacingString = "  ";
var sequenceFile = new StringBuffer();
var spacing = "##########################################################";

// collected state
var currentFeedValue = -1;
var optionalSection = false;
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

function getSequenceName(section) {
  var sequenceName = "";
  if (properties.useExternalSequencesFiles) {
    sequenceName += FileSystem.getFilename(getOutputPath().substr(0, getOutputPath().lastIndexOf("."))) + "_";
  }
  sequenceName += "SEQUENCE_" + mapComment(getOperationDescription(section));
  return sequenceName;
}

function getOperationName(section) {
  return "Operation_" + getOperationDescription(section);
}

function capitalizeFirstLetter(text) {
  return text.substring(0, 1).toUpperCase() + text.substring(1).toLowerCase();
}

function getSpacing() {
  var space = "";
  for (var i = 0; i < spacingDepth; i++) {
    space += spacingString;
  }
  return space;
}

/**
  Writes the specified block.
*/
function writeBlock() {
  var text = formatWords(arguments);
  writeWords(getSpacing() + text);
}

/**
  Output a comment.
*/
function writeComment(text) {
  if (text) {
    writeln(getSpacing() + "# " + text);
  }
}

var charMap = {
  "\u00c4" : "Ae",
  "\u00e4" : "ae",
  "\u00dc" : "Ue",
  "\u00fc" : "ue",
  "\u00d6" : "Oe",
  "\u00f6" : "oe",
  "\u00df" : "ss",
  "\u002d" : "_",
  "\u0020" : "_"
};

/** Map specific chars. */
function mapComment(text) {
  text = formatVariable(text);
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
  return String(text).replace(/[^A-Za-z0-9\-_]/g, "");
}

function onOpen() {
  // note: setup your machine here
  if (properties.got4thAxis) {
    var aAxis = createAxis({coordinate:0, table:true, axis:[1, 0, 0], range:[0, 360], cyclic:true, preference:0});
    machineConfiguration = new MachineConfiguration(aAxis);
    machineConfiguration.setVendor("DATRON");
    machineConfiguration.setModel("NEO with A Axis");
    machineConfiguration.setDescription("DATRON NEXT Control with additional A-Axis");
    setMachineConfiguration(machineConfiguration);
    optimizeMachineAngles2(1); // TCP mode 0:Full TCP 1: Map Tool Tip to Axis
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

  // write program calls
  var numberOfSections = getNumberOfSections();
  for (var i = 0; i < numberOfSections; ++i) {
    var section = getSection(i);
    var opName = getOperationName(section);
    var sectionID = i + 1;
    writeBlock(opName);
  }

  onCommand(COMMAND_COOLANT_OFF);

  writeBlock("Spindle Off");

  setWorkPlane(new Vector(0, 0, 0)); // reset working plane
  if (properties.useParkPosition) {
    writeBlock("MoveToParkPosition");
  } else {
    writeBlock("MoveToSafetyPosition");
    zOutput.reset();
  }

  spacingDepth -= 1;
  writeBlock("endprogram #" + (programName ? (SP + formatComment(programName)) : "") + ((unit == MM) ? " MM" : " INCH"));
  writeln("");
}

function getOperationDescription(section) {
  // creates the name of the operation
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

function createToolVariables() {
  var tools = getToolTable();
  if (tools.getNumberOfTools() > 0 && !properties.writeToolTable) {
    for (var i = 0; i < tools.getNumberOfTools(); ++i) {
      var tool = tools.getTool(i);
      writeBlock(toolOutput.format(tool.number) + ":number");
    }
    writeBlock(" ");
  }
}

function createToolDescriptionTable() {
  if (!properties.writeToolTable) {
    return;
  }
  var toolDescriptionArray = new Array();
  var toolNameList = new Array();
  var numberOfSections = getNumberOfSections();
  for (var i = 0; i < numberOfSections; ++i) {
    var section = getSection(i);
    var tool = section.getTool();
    if (tool.type != TOOL_PROBE) {
      var toolName = createToolName(tool);
      var toolProgrammed = createToolDescription(tool);
      if (toolNameList.indexOf(toolName) == -1) {
        toolNameList.push(toolName);
        toolDescriptionArray.push(toolProgrammed);
      } else {
/*
       if (toolDescriptionArray.indexOf(toolProgrammed) == -1) {
         error("\r\n#####################################\r\nOne ore more tools have the same name!\r\nPlease change the tool number to make the name unique.\r\n" + toolDescriptionArray.join("\r\n") + "\r\n\r\n" +
         toolNameList.join("\r\n") + "#####################################\r\n");
       }
*/
      }
    }
  }

  writeBlock(toolDescriptionArray.join("\r\n"));
}

function createToolDescription(tool) {
  var toolProgrammed = "@ ToolDescription : " +
      "\"" + "Name" + "\"" + ":" +  "\"" + createToolName(tool) + "\"" + ", " +
      "\"" + "Category" + "\"" + ":" +  "\"" + translateToolType(tool.type) + "\"" + ", " +
      "\"" + "ArticleNr" + "\"" + ":" +  "\"" + tool.productId + "\"" + ", " +
      "\"" + "ToolNumber" + "\"" + ":" + toolFormat.format(tool.number) + ", " +
      "\"" + "Vendor" + "\"" + ":" +  "\"" + tool.vendor + "\"" + ", " +
      "\"" + "Diameter" + "\"" + ":" + dimensionFormat.format(tool.diameter) + ", " +
      "\"" + "TipAngle" + "\"" + ":" + dimensionFormat.format(toDeg(tool.taperAngle)) + ", " +
      "\"" + "TipDiameter" + "\"" + ":" + dimensionFormat.format(tool.tipDiameter) + ", " +
      "\"" + "FluteLength" + "\"" + ":" + dimensionFormat.format(tool.fluteLength) + ", " +
      "\"" + "CornerRadius" + "\"" + ":" + dimensionFormat.format(tool.cornerRadius) + ", " +
      "\"" + "ShoulderLength" + "\"" + ":" + dimensionFormat.format(tool.shoulderLength) + ", " +
      "\"" + "ShoulderDiameter" + "\"" + ":" + dimensionFormat.format(tool.diameter) + ", " +
      "\"" + "BodyLength" + "\"" + ":" + dimensionFormat.format(tool.bodyLength) + ", " +
      "\"" + "NumberOfFlutes" + "\"" + ":" + toolFormat.format(tool.numberOfFlutes) + ", " +
      "\"" + "ThreadPitch" + "\"" + ":" + dimensionFormat.format(tool.threadPitch) + ", " +
      "\"" + "ShaftDiameter" + "\"" + ":" + dimensionFormat.format(tool.shaftDiameter) + ", " +
      "\"" + "OverallLength" + "\"" + ":" + dimensionFormat.format(tool.bodyLength + 2 * tool.shaftDiameter) +
      " @";
  return toolProgrammed;
}

/**
  Generate the logical tool name for the assignment table of used tools.
*/
function createToolName(tool) {
  var toolName = toolFormat.format(tool.number);
  toolName += "_" + translateToolType(tool.type);
  if (tool.comment) {
    toolName += "_" + tool.comment;
  }
  if (tool.diameter) {
    toolName += "_D" + tool.diameter;
  }
  var description = tool.getDescription();
  if (description) {
    toolName += "_" + description;
  }
  toolName = formatVariable(toolName);
  return toolName;
}

/**
  Translate HSM tools to Datron tool categories.
*/
function translateToolType(toolType) {

  var datronCategoryName = "";

  toolCategory = toolType;
  switch (toolType) {
  case TOOL_UNSPECIFIED:
    datronCategoryName = "Unspecified";
    break;
  case TOOL_DRILL:
    datronCategoryName = "Drill";
    break;
  case TOOL_DRILL_CENTER:
    datronCategoryName = "DrillCenter";
    break;
  case TOOL_DRILL_SPOT:
    datronCategoryName = "DrillSpot";
    break;
  case TOOL_DRILL_BLOCK:
    datronCategoryName = "DrillBlock";
    break;
  case TOOL_MILLING_END_FLAT:
    datronCategoryName = "MillingEndFlat";
    break;
  case TOOL_MILLING_END_BALL:
    datronCategoryName = "MillingEndBall";
    break;
  case TOOL_MILLING_END_BULLNOSE:
    datronCategoryName = "MillingEndBullnose";
    break;
  case TOOL_MILLING_CHAMFER:
    datronCategoryName = "Graver";
    break;
  case TOOL_MILLING_FACE:
    datronCategoryName = "MillingFace";
    break;
  case TOOL_MILLING_SLOT:
    datronCategoryName = "MillingSlot";
    break;
  case TOOL_MILLING_RADIUS:
    datronCategoryName = "MillingRadius";
    break;
  case TOOL_MILLING_DOVETAIL:
    datronCategoryName = "MillingDovetail";
    break;
  case TOOL_MILLING_TAPERED:
    datronCategoryName = "MillingTapered";
    break;
  case TOOL_MILLING_LOLLIPOP:
    datronCategoryName = "MillingLollipop";
    break;
  case TOOL_TAP_RIGHT_HAND:
    datronCategoryName = "TapRightHand";
    break;
  case TOOL_TAP_LEFT_HAND:
    datronCategoryName = "TapLeftHand";
    break;
  case TOOL_REAMER:
    datronCategoryName = "Reamer";
    break;
  case TOOL_BORING_BAR:
    datronCategoryName = "BoringBar";
    break;
  case TOOL_COUNTER_BORE:
    datronCategoryName = "CounterBore";
    break;
  case TOOL_COUNTER_SINK:
    datronCategoryName = "CounterSink";
    break;
  case TOOL_HOLDER_ONLY:
    datronCategoryName = "HolderOnly";
    break;
  case TOOL_PROBE:
    datronCategoryName = "XYZSensor";
    break;
  default:
    datronCategoryName = "Unspecified";
  }
  return datronCategoryName;
}

function writeProgramHeader() {
  // write creation Date
  var date = timeFormat.format(nowDay) + "." + timeFormat.format(nowMonth) + "." + now.getFullYear();
  var time = timeFormat.format(nowHour) + ":" + timeFormat.format(nowMin);
  writeComment("!File ; generated at " + date + " - " + time);
  if (programComment) {
    writeComment(formatComment(programComment));
  }

  writeBlock(" ");
  // dump machine configuration
  var vendor = machineConfiguration.getVendor();
  var model = machineConfiguration.getModel();
  var description = machineConfiguration.getDescription();

  if (properties.writeMachine && (vendor || model || description)) {
    writeComment(localize("Machine"));
    if (vendor) {
      writeComment("  " + localize("vendor") + ": " + vendor);
    }
    if (model) {
      writeComment("  " + localize("model") + ": " + model);
    }
    if (description) {
      writeComment("  " + localize("description") + ": " + description);
    }
  }

  writeBlock("module " + "CamGeneratedModule");
  writeBlock(" ");

  writeBlock("@ MeasuringSystem = " + (unit == MM ? "\"" + "Metric" + "\"" + " @" : "\"" + "Imperial" + "\"" + " @"));

  // write the table of used tools in the header of the program
  createToolDescriptionTable();
  writeBlock("");

  writeWorkpiece();

  // Creates the sequence header in the program file
  if (properties.useSequences) {
    var sequences = new Array();
    var numberOfSections = getNumberOfSections();
    for (var i = 0; i < numberOfSections; ++i) {
      var section = getSection(i);
			if (!isProbeOperation(section)) {
				sequences.push(getSequenceName(section));
			}
    }
    if (properties.useExternalSequencesFiles) {
      writeBlock("@ EmbeddedSequences = false @");
    }
    if (sequences.length > 0) {
      writeBlock("sequence " + sequences.join("\r\nsequence "));
      writeBlock(" ");
    }
  }

  // dont ask why the control need it
  writeBlock("using Base");
  if (properties.waitAfterOperation) {
    writeBlock("import System");
  }
  writeBlock(" ");

  // scan all operations for the parametric feed commands
  var feedDeclaration = new Array();
  var currentMovements = new Array();
  var numberOfSections = getNumberOfSections();
  for (var i = 0; i < numberOfSections; ++i) {
    var section = getSection(i);
    if (properties.useParametricFeed && (!useDatronFeedCommand)) {
      activeFeeds = initializeActiveFeeds(section);
      for (var j = 0; j < activeFeeds.length; ++j) {
        var feedContext = activeFeeds[j];
        var feedDescription = formatVariable(feedContext.description);
        if (feedDeclaration.indexOf(feedDescription) == -1) {
          feedDeclaration.push(feedDescription);
        }
      }
    }
  }

  // write all the variable declarations in the header of the program
  if (!useDatronFeedCommand) {
    writeComment("feed variables declaration");
    if (feedDeclaration != 0) {
      writeBlock(feedDeclaration.join(":number\r\n") + ":number\r\n");
    }
  }

  createToolVariables();

  writeBlock("export program Main # " + (programName ? (SP + formatComment(programName)) : "") + ((unit == MM) ? " MM" : " INCH"));
  spacingDepth += 1;

  writeBlock("Absolute");

  // write the parameter tool table
  if (!properties.writeToolTable) {
    var tools = getToolTable();
    writeComment("Number of tools in use" + ": " + tools.getNumberOfTools());
    if (tools.getNumberOfTools() > 0) {
      for (var i = 0; i < tools.getNumberOfTools(); ++i) {
        var tool = tools.getTool(i);
        var toolAsigment = toolOutput.format(tool.number) + " = " + (tool.number) + "# " +
          formatComment(getToolTypeName(tool.type)) + " " +
          "D:" + dimensionFormat.format(tool.diameter) + " " +
          "L2:" + dimensionFormat.format(tool.fluteLength) + " " +
          "L3:" + dimensionFormat.format(tool.shoulderLength) + " " +
          "ProductID:" + formatComment(tool.productId);
        writeBlock(toolAsigment);
      }
      writeBlock(" ");
    }
  }
}


function writeWorkpiece() {
  var workpiece = getWorkpiece();
  var delta = Vector.diff(workpiece.upper, workpiece.lower);

  writeBlock("# Workpiece dimensions");
  writeBlock(
    "# min:      X: " + workpieceFormat.format(workpiece.lower.x) + ";" +
    " Y: " + workpieceFormat.format(workpiece.lower.y) + ";" +
    " Z: " + workpieceFormat.format(workpiece.lower.z));
  writeBlock(
    "# max:      X: " + workpieceFormat.format(workpiece.upper.x) + ";" +
    " Y: " + workpieceFormat.format(workpiece.upper.y) + ";" +
    " Z: " + workpieceFormat.format(workpiece.upper.z));
  writeBlock(
    "# Part size X: " + workpieceFormat.format(delta.x) + ";" +
    " Y: " + workpieceFormat.format(delta.y) + ";" +
    " Z: " + workpieceFormat.format(delta.z));

  writeBlock("@ WorkpieceGeometry : " + "\"" + "MinEdge" + "\"" + ":{" + "\"" + "X" + "\"" + ":" + workpieceFormat.format(workpiece.lower.x) + "," +
    "\"" + "Y" + "\"" + ":" + workpieceFormat.format(workpiece.lower.y) + "," +
    "\"" + "Z" + "\"" + ":" +  workpieceFormat.format(workpiece.lower.z) + "}," +
    "\"" + "MaxEdge" + "\"" + ":{" + "\"" +"X" + "\"" + ":" + workpieceFormat.format(workpiece.upper.x) + "," +
    "\"" + "Y" + "\"" + ":" + workpieceFormat.format(workpiece.upper.y) + "," +
    "\"" + "Z" + "\"" + ":" + workpieceFormat.format(workpiece.upper.z) + "}" +
    " @");
  writeBlock(" ");
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

function FeedContext(id, description, datronFeedName, feed) {
  this.id = id;
  this.description = description;
  this.datronFeedName = datronFeedName;
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
        if (useDatronFeedCommand) {
          return ("Feed " + capitalizeFirstLetter(feedContext.datronFeedName));
        } else {
          return ("Feed=" + formatVariable(feedContext.description));
        }
      }
    }
    currentFeedId = undefined; // force Q feed next time
  }
  if (feedFormat.areDifferent(currentFeedValue, f)) {
    currentFeedValue = f;
    return "Feed=" + feedFormat.format(f);
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
      var feedContext = new FeedContext(id, localize("Cutting"), "roughing", section.getParameter("operation:tool_feedCutting"));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_CUTTING] = feedContext;
      activeMovements[MOVEMENT_LINK_TRANSITION] = feedContext;
      activeMovements[MOVEMENT_EXTENDED] = feedContext;
    }
    ++id;
    if (movements & (1 << MOVEMENT_PREDRILL)) {
      feedContext = new FeedContext(id, localize("Predrilling"), "plunge", section.getParameter("operation:tool_feedCutting"));
      activeMovements[MOVEMENT_PREDRILL] = feedContext;
      addFeedContext(feedContext, activeFeeds);
    }
    ++id;
    if (section.hasParameter("operation-strategy") && (section.getParameter("operation-strategy") == "drill")) {
      var feedContext = new FeedContext(id, localize("Cutting"), "roughing", section.getParameter("operation:tool_feedCutting"));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_CUTTING] = feedContext;
    }
    ++id;
  }
  if (section.hasParameter("operation:finishFeedrate")) {
    if (movements & (1 << MOVEMENT_FINISH_CUTTING)) {
      var feedContext = new FeedContext(id, localize("Finish"), "finishing", section.getParameter("operation:finishFeedrate"));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_FINISH_CUTTING] = feedContext;
    }
    ++id;
  } else if (section.hasParameter("operation:tool_feedCutting")) {
    if (movements & (1 << MOVEMENT_FINISH_CUTTING)) {
      var feedContext = new FeedContext(id, localize("Finish"), "finishing", section.getParameter("operation:tool_feedCutting"));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_FINISH_CUTTING] = feedContext;
    }
    ++id;
  }
  if (section.hasParameter("operation:tool_feedEntry")) {
    if (movements & (1 << MOVEMENT_LEAD_IN)) {
      var feedContext = new FeedContext(id, localize("Entry"), "approach", section.getParameter("operation:tool_feedEntry"));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_LEAD_IN] = feedContext;
    }
    ++id;
  }
  if (section.hasParameter("operation:tool_feedExit")) {
    if (movements & (1 << MOVEMENT_LEAD_OUT)) {
      var feedContext = new FeedContext(id, localize("Exit"), "approach", section.getParameter("operation:tool_feedExit"));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_LEAD_OUT] = feedContext;
    }
    ++id;
  }
  if (section.hasParameter("operation:noEngagementFeedrate")) {
    if (movements & (1 << MOVEMENT_LINK_DIRECT)) {
      var feedContext = new FeedContext(id, localize("Direct"), "approach", section.getParameter("operation:noEngagementFeedrate"));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_LINK_DIRECT] = feedContext;
    }
    ++id;
  } else if (section.hasParameter("operation:tool_feedCutting") &&
    section.hasParameter("operation:tool_feedEntry") &&
    section.hasParameter("operation:tool_feedExit")) {
    if (movements & (1 << MOVEMENT_LINK_DIRECT)) {
      var feedContext = new FeedContext(id, localize("Direct"), "approach", Math.max(section.getParameter("operation:tool_feedCutting"), section.getParameter("operation:tool_feedEntry"), section.getParameter("operation:tool_feedExit")));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_LINK_DIRECT] = feedContext;
    }
    ++id;
  }
  if (section.hasParameter("operation:reducedFeedrate")) {
    if (movements & (1 << MOVEMENT_REDUCED)) {
      var feedContext = new FeedContext(id, localize("Reduced"), "finishing", section.getParameter("operation:reducedFeedrate"));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_REDUCED] = feedContext;
    }
    ++id;
  }
  if (section.hasParameter("operation:tool_feedRamp")) {
    if (movements & ((1 << MOVEMENT_RAMP) | (1 << MOVEMENT_RAMP_HELIX) | (1 << MOVEMENT_RAMP_PROFILE) | (1 << MOVEMENT_RAMP_ZIG_ZAG))) {
      var feedContext = new FeedContext(id, localize("Ramping"), "ramp", section.getParameter("operation:tool_feedRamp"));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_RAMP] = feedContext;
      activeMovements[MOVEMENT_RAMP_HELIX] = feedContext;
      activeMovements[MOVEMENT_RAMP_PROFILE] = feedContext;
      activeMovements[MOVEMENT_RAMP_ZIG_ZAG] = feedContext;
    }
    ++id;
  }
  if (section.hasParameter("operation:tool_feedPlunge")) {
    if (movements & (1 << MOVEMENT_PLUNGE)) {
      var feedContext = new FeedContext(id, localize("Plunge"), "plunge", section.getParameter("operation:tool_feedPlunge"));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_PLUNGE] = feedContext;
    }
    ++id;
  }

  // this part allows us to use feedContext also for the cycles
  if (hasParameter("operation:cycleType")) {
    var cycleType = getParameter("operation:cycleType");
    if (hasParameter("movement:plunge")) {
      var feedContext = new FeedContext(id, localize("Plunge"), "plunge", section.getParameter("movement:plunge"));
      addFeedContext(feedContext, activeFeeds);
      ++id;
    }

    switch (cycleType) {
    case "thread-milling":
      if (hasParameter("movement:plunge")) {
        var feedContext = new FeedContext(id, localize("Plunge"), "plunge", section.getParameter("movement:plunge"));
        addFeedContext(feedContext, activeFeeds);
        ++id;
      }
      if (hasParameter("movement:ramp")) {
        var feedContext = new FeedContext(id, localize("Ramping"), "ramp", section.getParameter("movement:ramp"));
        addFeedContext(feedContext, activeFeeds);
        ++id;
      }
      if (hasParameter("movement:finish_cutting")) {
        var feedContext = new FeedContext(id, localize("Finish"), "finishing", section.getParameter("movement:finish_cutting"));
        addFeedContext(feedContext, activeFeeds);
        ++id;
      }
      break;
    case "bore-milling":
      if (section.hasParameter("movement:plunge")) {
        var feedContext = new FeedContext(id, localize("Plunge"), "plunge", section.getParameter("movement:plunge"));
        addFeedContext(feedContext, activeFeeds);
        ++id;
      }
      if (section.hasParameter("movement:ramp")) {
        var feedContext = new FeedContext(id, localize("Ramping"), "ramp", section.getParameter("movement:ramp"));
        addFeedContext(feedContext, activeFeeds);
        ++id;
      }
      if (hasParameter("movement:finish_cutting")) {
        var feedContext = new FeedContext(id, localize("Finish"), "finishing", section.getParameter("movement:finish_cutting"));
        addFeedContext(feedContext, activeFeeds);
        ++id;
      }
      break;
    }
  }

  if (true) { // high feed
    if (movements & (1 << MOVEMENT_HIGH_FEED)) {
      var feedContext = new FeedContext(id, localize("High Feed"), "roughing", this.highFeedrate);
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_HIGH_FEED] = feedContext;
    }
    ++id;
  }
  return activeFeeds;
}

/** Check that all elements are only one time in the result list. */
function addFeedContext(feedContext, activeFeeds) {
  if (activeFeeds.indexOf(feedContext) == -1) {
    activeFeeds.push(feedContext);
  }
}

var currentWorkPlaneABC = undefined;

function forceWorkPlane() {
  currentWorkPlaneABC = undefined;
}

function setWorkPlane(abc) {
  if (!machineConfiguration.isMultiAxisConfiguration()) {
    return; // ignore
  }

  forceWorkPlane(); // always need the new workPlane
	forceABC();

  writeBlock("MoveToSafetyPosition");
  writeBlock("Rapid" + aOutput.format(abc.x) + bOutput.format(abc.y) + cOutput.format(abc.z));

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
      + conditional(machineConfiguration.isMachineCoordinate(2), " C" + abcFormat.format(abc.z)));
  }

  var direction = machineConfiguration.getDirection(abc);
  if (!isSameDirection(direction, W.forward)) {
    error(localize("Orientation not supported."));
  }

  if (!machineConfiguration.isABCSupported(abc)) {
    error(
      localize("Work plane is not supported") + ":"
      + conditional(machineConfiguration.isMachineCoordinate(0), " A" + abcFormat.format(abc.x))
      + conditional(machineConfiguration.isMachineCoordinate(1), " B" + abcFormat.format(abc.y))
      + conditional(machineConfiguration.isMachineCoordinate(2), " C" + abcFormat.format(abc.z)));
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

function onSection() {
	/*
  if (isProbeOperation(currentSection)) {
    // TAG: remove once probing is supported properly, waiting for Datron
    error(localize("Probing is not supported for now."));
    return;
  }
	*/

  var forceToolAndRetract = optionalSection && !currentSection.isOptional();
  optionalSection = currentSection.isOptional();
  var tool = currentSection.getTool();

  if (!isProbeOperation(currentSection)) {
    writeComment("Operation Time: " + formatCycleTime(currentSection.getCycleTime()));
  }

  var showToolZMin = true;
  if (showToolZMin) {
    if (is3D()) {
      var zRange = currentSection.getGlobalZRange();
      var number = tool.number;
      zRange.expandToRange(currentSection.getGlobalZRange());
      writeComment("ZMIN = " + xyzFormat.format(zRange.getMinimum()));
    }
  }

  // create sub program
  writeBlock("program " + getOperationName(currentSection));
  spacingDepth += 1;

  if (passThrough) {
    var joinString = "\r\n" + getSpacing();
    var passThroughString = passThrough.join(joinString);
    if (passThroughString != "") {
      writeBlock(passThroughString);
    }
    passThrough = [];
  }

  // this control structure allows us to show the user the operation from the CAM application as a block of within the whole program similarly to Heidenhain structure.
  writeBlock("BeginBlock name=" + "\"" + getOperationDescription(currentSection) + "\"");
  var operationTolerance = tolerance;
  if (hasParameter("operation:tolerance")) {
    if (operationTolerance < getParameter("operation:tolerance")) {
      operationTolerance = getParameter("operation:tolerance");
    }
  }

	//load the matching workOffset
	var workOffset = currentSection.getWorkOffset();
	if (workOffset != 0) {
		writeBlock("LoadWcs name=\"" + workOffset +"\"");
	}
	
  if (properties.useSmoothing && !currentSection.isMultiAxis() && !isProbeOperation(currentSection)) {
    writeBlock("Smoothing On allowedDeviation=" + xyzFormat.format(operationTolerance * 1.2));
  } else
  {
    writeBlock("Smoothing Off");
  }

  if (properties.useDynamic) {

    var dynamic = 5;
		/*
    if (operationTolerance <= 0.02) {
      dynamic = 4;
    }
    if (operationTolerance <= 0.01) {
      dynamic = 3;
    }
    if (operationTolerance <= 0.005) {
      dynamic = 2;
    }
    if (operationTolerance <= 0.003) {
      dynamic = 1;
    }
		*/
    writeBlock("Dynamic = " + dynamic);
  }
  if (properties.waitAfterOperation) {
    showWaitDialog();
  }

  if (machineConfiguration.isMultiAxisConfiguration()) {
    if (currentSection.isMultiAxis()) {
      forceWorkPlane();
      cancelTransformation();
      var abc = currentSection.getInitialToolAxisABC();
      writeBlock("MoveToSafetyPosition");
      writeBlock("Rapid" + aOutput.format(abc.x) + bOutput.format(abc.y) + cOutput.format(abc.z));
    } else {
			forceWorkPlane();
      var abc = getWorkPlaneMachineABC(currentSection.workPlane);
      setWorkPlane(abc);
    }
  } else {
    // pure 3D
    var remaining = currentSection.workPlane;
    if (!isSameDirection(remaining.forward, new Vector(0, 0, 1)) || currentSection.isMultiAxis()) {
      error("\r\n_________________________________________" +
         "\r\n|              error                     |" +
         "\r\n|                                        |" +
         "\r\n| Tool orientation detected.             |" +
         "\r\n| You have to enable the property        |" +
         "\r\n| got4thAxis, otherwise you can only post|" +
         "\r\n| 3 Axis programs.                       |" +
         "\r\n| If you still have issues,              |" +
         "\r\n| please contact www.DATRON.com!         |" +
         "\r\n|________________________________________|\r\n");
      return;
    }
    setRotation(remaining);
  }
  
  forceAny();

  if (properties.showNotes && currentSection.hasParameter("notes")) {
    var notes = currentSection.getParameter("notes");
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

  var clearance = getFramePosition(currentSection.getInitialPosition()).z;
  writeBlock("SafeZHeightForWorkpiece=" + xyzFormat.format(clearance));

  if (!isProbeOperation(currentSection)) {
    // set rpm
    if ((tool.spindleRPM < 6000) && (tool.spindleRPM > 0)) {
      tool.spindleRPM = 6000;
    }

    // set coolant after we have positioned at Z
    setCoolant(tool.coolant);

    // tool changer command
    if (properties.writeToolTable) {
      writeBlock("Tool name=" + "\"" + createToolName(tool) + "\"" +
        " newRpm=" + rpmFormat.format(tool.spindleRPM) +
        " skipRestoring"
      );
    } else {
      writeBlock("Tool = " + toolOutput.format(tool.number) +
        " newRpm=" + rpmFormat.format(tool.spindleRPM) +
        " skipRestoring"
      );
    }

    // set the current feed
    // replace by the default feed command
    if (properties.useParametricFeed && !(currentSection.hasAnyCycle && currentSection.hasAnyCycle())) {
      activeFeeds = initializeActiveFeeds(currentSection);
      if (useDatronFeedCommand) {
        var datronFeedParameter = new Array();
        for (var j = 0; j < activeFeeds.length; ++j) {
          var feedContext = activeFeeds[j];
          var datronFeedCommand = {
            name : feedContext.datronFeedName,
            feed : feedFormat.format(feedContext.feed)
          };
/*eslint-disable*/
          var indexOfFeedContext = datronFeedParameter.map(function(e) {return e.name;}).indexOf(datronFeedCommand.name);
/*eslint-enable*/
          if (indexOfFeedContext == -1) {
            datronFeedParameter.push(datronFeedCommand);
          } else {
            var existingFeedContext = datronFeedParameter[indexOfFeedContext];
            if (existingFeedContext.feed < datronFeedCommand.feed) {
              existingFeedContext.feed = datronFeedCommand.feed;
            }
          }
        }
        var datronFeedCommand = "SetFeedTechnology";
        for (var i = 0; i < datronFeedParameter.length; i++) {
          datronFeedCommand += " " + datronFeedParameter[i].name + "=" + datronFeedParameter[i].feed;
        }
        writeBlock(datronFeedCommand);

      } else {
        for (var j = 0; j < activeFeeds.length; ++j) {
          var feedContext = activeFeeds[j];
          writeBlock(formatVariable(feedContext.description) + " = " + feedFormat.format(feedContext.feed) + (unit == MM ? " # mm/min!" : " # in/min!"));
        }
      }
    }
  }

  // parameter for the sequences
  var sequenceParamter = new Array();

  if (hasParameter("operation:cycleType")) {
		
		//Reset all movements to suppress older entries...
		activeMovements = new Array();
		
    var cycleType = getParameter("operation:cycleType");
    writeComment("Parameter " + cycleType + " cycle");

    switch (cycleType) {
    case "thread-milling":
      writeBlock("SetFeedTechnology" + " ramp=" + feedFormat.format(getParameter("movement:cutting")) + " finishing=" + feedFormat.format(getParameter("movement:finish_cutting")));
      var diameter = currentSection.getParameter("diameter");
      var pitch = currentSection.getParameter("pitch");
      var finishing = currentSection.getParameter("stepover");

      writeBlock("nominalDiameter=" + xyzFormat.format(diameter));
      sequenceParamter.push("nominalDiameter=nominalDiameter");
      writeBlock("pitch=" + xyzFormat.format(pitch));
      sequenceParamter.push("pitch=pitch");
      if (xyzFormat.isSignificant(finishing)) {
        writeBlock("finishing=" + xyzFormat.format(finishing));
        sequenceParamter.push("finishing=finishing");
      } else {
        sequenceParamter.push("finishing=0");
      }
/*
      writeBlock('threadName="M' +  toolFormat.format(diameter) + '"');
      sequenceParamter.push('threadName=threadName');
      writeBlock("threading = " + currentSection.getParameter("threading"));
      sequenceParamter.push("threading=threading");

      TAG: den Standard auch mit Imperial unterstuezten
      sequenceParamter.push("threadStandard=ThreadStandards.Metric");
      sequenceParamter.push("deburring=ThreadMillingDeburring.NoDeburring");
      sequenceParamter.push("insideOutside=ThreadMillingSide.Inside");
      sequenceParamter.push("direction=ThreadMillingDirection.RightHandThread");
      writeBlock("direction = " + dimensionFormat.format(currentSection.getParameter("direction")));
      sequenceParamter.push("direction=direction");
      writeBlock("repeatPass = " + dimensionFormat.format(currentSection.getParameter("repeatPass")));
      sequenceParamter.push("repeatPass=repeatPass");
*/
      break;
    case "bore-milling":
      writeBlock("SetFeedTechnology roughing=" + feedFormat.format(getParameter("movement:cutting")) + " finishing=" + feedFormat.format(getParameter("movement:cutting")));
      writeBlock("diameter = " + dimensionFormat.format(currentSection.getParameter("diameter")));
      sequenceParamter.push("diameter=diameter");

      writeBlock("infeedZ = " + dimensionFormat.format(currentSection.getParameter("pitch")));
      sequenceParamter.push("infeedZ=infeedZ");
      writeBlock("repeatPass = " + dimensionFormat.format(currentSection.getParameter("repeatPass")));
      sequenceParamter.push("repeatPass=repeatPass");
      break;
    case "drilling":
      writeBlock("SetFeedTechnology plunge=" + feedFormat.format(getParameter("movement:plunge")));
      break;
  case "chip-breaking":
      writeBlock("SetFeedTechnology plunge=" + feedFormat.format(getParameter("movement:plunge")) + " roughing=" + feedFormat.format(getParameter("movement:cutting")));
      writeBlock("infeedZ = " + dimensionFormat.format(currentSection.getParameter("incrementalDepth")));
      sequenceParamter.push("infeedZ=infeedZ");
      break;
    }
  }

  if (properties.useSequences && !isProbeOperation(currentSection)) {
    // call sequence
    if (properties.useParametricFeed && (!useDatronFeedCommand) && !(currentSection.hasAnyCycle && currentSection.hasAnyCycle())) {
      activeFeeds = initializeActiveFeeds(currentSection);
      for (var j = 0; j < activeFeeds.length; ++j) {
        var feedContext = activeFeeds[j];
        sequenceParamter.push(formatVariable(feedContext.description) + "=" + formatVariable(feedContext.description));
      }
    }
    var currentSectionCall = getSequenceName(currentSection) + " " + sequenceParamter.join(" ");
    writeBlock(currentSectionCall);

    // write sequence
    var currentSequenceName = getSequenceName(currentSection);
    if (properties.useExternalSequencesFiles) {
      spacingDepth -= 1;
      var filename = getOutputPath();
      //sequenceFilePath = filename.substr(0, filename.lastIndexOf(".")) + "_" + currentSequenceName + ".seq";
      sequenceFilePath = FileSystem.getFolderPath(getOutputPath()) + "\\";
      sequenceFilePath += currentSequenceName + ".seq";
      redirectToFile(sequenceFilePath);
    } else {
      redirectToBuffer();
      writeBlock(" ");
      // TAG: modify parameter
      spacingDepth -= 1;
      writeBlock("$$$ " + currentSequenceName);
    }
  }

  if (!isProbeOperation(currentSection)) {
		writeBlock(tool.spindleRPM > 100 ? "Spindle On" : "Spindle Off");
  } else {
    writeBlock("Spindle Off");
    writeBlock("PrepareXyzSensor");
  }

  // move to initial Position (this command move the Z Axis to safe high and repositioning in safe high after that drive Z to end position)
  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  var xyz = xOutput.format(initialPosition.x) + yOutput.format(initialPosition.y) + zOutput.format(initialPosition.z);
  writeBlock("PrePositioning" + xyz);
}


function showWaitDialog(operationName) {
  writeBlock("showWaitDialog");
}

function writeWaitProgram() {
  writeBlock("#Show the wait dialog for the next operation");
  writeBlock("program showWaitDialog optional operationName:string");
  writeBlock("");
  writeBlock("  if not operationName hasvalue ");
  writeBlock("    operationName =" + "\"" + "\"");
  writeBlock("  endif");
  writeBlock("");
  writeBlock("  messageString = " + "\"" + "Start next Operation\r"  + "\"" + "  + operationName ");
  writeBlock("  dialogResult = System::Dialog message=messageString caption=" + "\"" + "Start next Operation?" + "\"" + "Yes  Cancel");
  writeBlock("  if dialogResult == System::DialogResult.Cancel");
  writeBlock("    exit");
  writeBlock("  endif");
  writeBlock("");
  writeBlock("endprogram");
}

function onDwell(seconds) {
  writeln("Sleep " + "milliseconds=" + sleepFormat.format(seconds));
}

function onSpindleSpeed(spindleSpeed) {
  writeBlock("Rpm=" + rpmFormat.format(tool.spindleRPM));
}

var pendingRadiusCompensation = -1;

function onRadiusCompensation() {
  pendingRadiusCompensation = radiusCompensation;
}

function onRapid(x, y, z) {
  var xyz = "";
  xyz += (x !== null) ? xOutput.format(x) : "";
  xyz += (y !== null) ? yOutput.format(y) : "";
  xyz += (z !== null) ? zOutput.format(z) : "";

  if (xyz) {
    if (pendingRadiusCompensation >= 0) {
      error(localize("Radius compensation mode cannot be changed at rapid traversal."));
      return;
    }
    writeBlock("Rapid" + xyz);
    forceFeed();
  }
}

function onPrePositioning(x, y, z) {
  var xyz = "";
  xyz += (x !== null) ? xOutput.format(x) : "";
  xyz += (y !== null) ? yOutput.format(y) : "";
  xyz += (z !== null) ? zOutput.format(z) : "";

  if (xyz) {
    if (pendingRadiusCompensation >= 0) {
      error(localize("Radius compensation mode cannot be changed at rapid traversal."));
      return;
    }
    writeBlock("PrePositioning" + xyz);
    forceFeed();
  }
}

function onLinear(x, y, z, feed) {
  var xyz = "";
  xyz += (x !== null) ? xOutput.format(x) : "";
  xyz += (y !== null) ? yOutput.format(y) : "";
  xyz += (z !== null) ? zOutput.format(z) : "";

  var f = getFeed(feed);

  if (pendingRadiusCompensation >= 0) {
    pendingRadiusCompensation = -1;
    var d = tool.diameterOffset;
    if (d > 99) {
      warning(localize("The diameter offset exceeds the maximum value."));
    }
    // TAG: um die Ebenen kuemmern
    // writeBlock(gPlaneModal.format(17));
    switch (radiusCompensation) {
    case RADIUS_COMPENSATION_LEFT:
      writeBlock("ToolCompensation Left");
      break;
    case RADIUS_COMPENSATION_RIGHT:
      writeBlock("ToolCompensation Right");
      break;
    case RADIUS_COMPENSATION_OFF:
      writeBlock("ToolCompensation Off");
      break;
    }
  }

  if (xyz) {
    if (f) {
      writeBlock(f);
    }
    writeBlock("Line" + xyz);
  }
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  // one of X/Y and I/J are required and likewise
  var f = getFeed(feed);

  if (f) {
    writeBlock(f);
  }

  if (pendingRadiusCompensation >= 0) {
    error(localize("radius compensation cannot be activated/deactivated for a circular move."));
    return;
  }

  var start = getCurrentPosition();

  if (isFullCircle()) {
    if (isHelical()) {
      linearize(tolerance);
      return;
    }
    // TAG: are 360deg arcs supported
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock("Arc" +
        (clockwise ? " CW" : " CCW") +
        xOutput.format(x) +
        iOutput.format(cx - start.x) +
        jOutput.format(cy - start.y)
      );
      break;
    default:
      linearize(tolerance);
    }
  } else {
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock("Arc" +
        (clockwise ? " CW" : " CCW") +
        xOutput.format(x) +
        yOutput.format(y) +
        zOutput.format(z) +
        iOutput.format(cx - start.x) +
        jOutput.format(cy - start.y)
      );
      break;
    default:
      linearize(tolerance);
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
  var a = aOutput.format(_a);
  var b = bOutput.format(_b);
  var c = cOutput.format(_c);

  forceABC();
  var xyzabc = x + y + z + a + b + c;
  writeBlock("Rapid" + xyzabc);
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
  var a = aOutput.format(_a);
  var b = bOutput.format(_b);
  var c = cOutput.format(_c);
  var f = getFeed(feed);

  writeBlock(f);
  if (x || y || z || a || b || c) {
    var xyzabc = x + y + z + a + b + c;
    writeBlock("Line" + xyzabc);
  } else if (f) {
    if (getNextRecord().isMotion()) { // try not to output feed without motion
      forceFeed(); // force feed on next line
    } else {
      writeBlock(getFeed(feed));
    }
  }
}

function onRewindMachine(a, b, c) {
  writeBlock("MoveToSafetyPosition");
  var abc = aOutput.format(a) + bOutput.format(b) + cOutput.format(c);
  writeBlock("Line" + abc);
}

var currentCoolantMode = COOLANT_OFF;

function setCoolant(coolant) {
  if (properties.writeCoolantCommands) {
    if (coolant == COOLANT_OFF) {
      writeBlock("SpraySystem Off");
      currentCoolantMode = COOLANT_OFF;
      return;
    }

    var m;
    switch (coolant) {
    case COOLANT_FLOOD:
    case COOLANT_MIST:
      writeBlock("Coolant Alcohol");
      break;
    case COOLANT_AIR:
      writeBlock("Coolant Air");
      break;
    default:
      onUnsupportedCoolant(coolant);
    }
    writeBlock("SpraySystem On");
    currentCoolantMode = coolant;
  }
}

var mapCommand = {};

var passThrough = new Array();

function onPassThrough(text) {
  passThrough.push(text);
}

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

function onCycle() {
}

function onCycleEnd() {
}

function isProbeOperation(section) {
  return (section.hasParameter("operation-strategy") && section.getParameter("operation-strategy") == "probe");
}

function approach(value) {
  validate((value == "positive") || (value == "negative"), "Invalid approach.");
  return (value == "positive") ? 1 : -1;
}

function onCyclePoint(x, y, z) {
  var feedString = feedOutput.format(cycle.feedrate);

  if (isProbeOperation(currentSection)) {
    if (!isSameDirection(currentSection.workPlane.forward, new Vector(0, 0, 1)) && (!cycle.probeMode || (cycle.probeMode == 0))) {
      error(localize("Updating WCS / work offset using probing is only supported by the CNC in the WCS frame."));
      return;
    }
  
    var startPositionOffset = cycle.probeClearance + tool.cornerRadius;
  }

  switch (cycleType) {
  case "bore-milling":
    for (var i = 0; i <= cycle.repeatPass; ++i) {
      forceXYZ();
      onRapid(x, y, cycle.clearance);
      boreMilling(cycle);
      onRapid(x, y, cycle.clearance);
    }
    break;
  case "thread-milling":
    for (var i = 0; i <= cycle.repeatPass; ++i) {
      forceXYZ();
      onRapid(x, y, cycle.clearance);
      threadMilling(cycle);
      onRapid(x, y, cycle.clearance);
    }
    break;
  case "drilling":
    forceXYZ();
    onRapid(x, y, cycle.clearance);
    drilling(cycle);
    onRapid(x, y, cycle.clearance);
    break;
/*
  case "chip-breaking":
    forceXYZ();
    onRapid(x, y, null);
    onRapid(x, y, cycle.retract);
    chipBreaking(cycle);
    onRapid(x, y, cycle.clearance);
    break;
*/
  case "probing-x":
    forceXYZ();
    onRapid(x, y, cycle.stock);
    onLinear(x, y, (z - cycle.depth + tool.cornerRadius), cycle.feedrate);
   
    var measureString = "EdgeMeasure ";
    measureString += (cycle.approach1 == "positive" ? "XPositive" : "XNegative");
    measureString += " originShift=" + xyzFormat.format(-1 * (x + approach(cycle.approach1) * startPositionOffset));
    measureString += " searchDistance=" + xyzFormat.format(cycle.probeClearance);
    writeBlock(measureString);
    break;
  case "probing-y":
    forceXYZ();
    onRapid(x, y, cycle.stock);
    onLinear(x, y, (z - cycle.depth + tool.cornerRadius), cycle.feedrate);
    
    var measureString = "EdgeMeasure ";
    measureString += (cycle.approach1 == "positive" ? "YPositive" : "YNegative");
    measureString += " originShift=" + xyzFormat.format(-1 * (y + approach(cycle.approach1) * startPositionOffset));
    measureString += " searchDistance=" + xyzFormat.format(cycle.probeClearance);
    writeBlock(measureString);
    break;
  case "probing-z":
    forceXYZ();
    onRapid(x, y, cycle.stock);
    onLinear(x, y, (Math.min(z - cycle.depth + cycle.probeClearance, cycle.retract)), cycle.feedrate);
  
    var measureString = "SurfaceMeasure ";
    measureString += " originZShift=" + xyzFormat.format(z - cycle.depth);
    writeBlock(measureString);
    break;
  case "probing-x-wall":
    var measureString = "SymmetryAxisMeasure";
    measureString += " width=" + cycle.width1;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " measureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Outside";
    measureString += " YAligned";
    measureString += " skipZMeasure";
    measureString += " originXShift=" + xyzFormat.format(-x);
    writeBlock(measureString);
    break;
  case "probing-y-wall":
    var measureString = "SymmetryAxisMeasure";
    measureString += " width=" + cycle.width1;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " measureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Outside";
    measureString += " XAligned";
    measureString += " skipZMeasure";
    measureString += " originYShift=" + xyzFormat.format(-y);
    writeBlock(measureString);
    break;
  case "probing-x-channel":
    var measureString = "SymmetryAxisMeasure";
    measureString += " width=" + cycle.width1;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " measureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Inside";
    measureString += " YAligned";
    measureString += " skipZMeasure";
     measureString += " originXShift=" + xyzFormat.format(-x);
    writeBlock(measureString);
    break;
  case "probing-x-channel-with-island":
    var measureString = "SymmetryAxisMeasure";
    measureString += " width=" + cycle.width1;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " measureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Inside";
    measureString += " YAligned";
    measureString += " forceSafeHeight";
    measureString += " skipZMeasure";
    measureString += " originXShift=" + xyzFormat.format(-x);
    writeBlock(measureString);
    break;
  case "probing-y-channel":
    var measureString = "SymmetryAxisMeasure";
    measureString += " width=" + cycle.width1;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " measureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Inside";
    measureString += " XAligned";
    measureString += " skipZMeasure";
    measureString += " originYShift=" + xyzFormat.format(-y);
    writeBlock(measureString);
    break;
  case "probing-y-channel-with-island":
    var measureString = "SymmetryAxisMeasure";
    measureString += " width=" + cycle.width1;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " measureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Inside";
    measureString += " XAligned";
    measureString += " forceSafeHeight";
    measureString += " skipZMeasure";
    measureString += " originYShift=" + xyzFormat.format(-y);
     writeBlock(measureString);
    break;
  case "probing-xy-circular-boss":
    var measureString = "CircleMeasure";
    measureString += " diameter=" + cycle.width1;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " measureZPos=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Outside";
    measureString += " skipZMeasure";
    measureString += " originXShift=" + xyzFormat.format(-x);
    measureString += " originYShift=" + xyzFormat.format(-y);
    writeBlock(measureString);
    break;
  case "probing-xy-circular-hole":
    var measureString = "CircleMeasure";
    measureString += " diameter=" + cycle.width1;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " measureZPos=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Inside";
    measureString += " skipZMeasure";
    measureString += " originXShift=" + xyzFormat.format(-x);
    measureString += " originYShift=" + xyzFormat.format(-y);
    writeBlock(measureString);
    break;
  case "probing-xy-circular-hole-with-island":
    var measureString = "CircleMeasure";
    measureString += " diameter=" + cycle.width1;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " measureZPos=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Inside";
    measureString += " forceSafeHeight";
    measureString += " skipZMeasure";
    measureString += " originXShift=" + xyzFormat.format(-x);
    measureString += " originYShift=" + xyzFormat.format(-y);
    writeBlock(measureString);
    break;
  case "probing-xy-rectangular-boss":
    var measureString = "RectangleMeasure";
    measureString += " dimensionX=" + cycle.width1;
    measureString += " dimensionY=" + cycle.width2;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " xMeasureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " yMeasureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Outside";
    measureString += " Center";
    measureString += " skipZMeasure";
    measureString += " originXShift=" + xyzFormat.format(-x);
    measureString += " originYShift=" + xyzFormat.format(-y);
    writeBlock(measureString);
    break;
  case "probing-xy-rectangular-hole":
    var measureString = "RectangleMeasure";
    measureString += " dimensionX=" + cycle.width1;
    measureString += " dimensionY=" + cycle.width2;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " xMeasureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " yMeasureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Inside";
    measureString += " Center";
    measureString += " skipZMeasure";
    measureString += " originXShift=" + xyzFormat.format(-x);
    measureString += " originYShift=" + xyzFormat.format(-y);
    writeBlock(measureString);
    break;
  case "probing-xy-rectangular-hole-with-island":
    var measureString = "RectangleMeasure";
    measureString += " dimensionX=" + cycle.width1;
    measureString += " dimensionY=" + cycle.width2;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " xMeasureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " yMeasureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Inside";
    measureString += " Center";
    measureString += " forceSafeHeight";
    measureString += " skipZMeasure";
    measureString += " originXShift=" + xyzFormat.format(-x);
    measureString += " originYShift=" + xyzFormat.format(-y);
    writeBlock(measureString);
    break;
  case "probing-xy-inner-corner":
    var probingDepth = (z - cycle.depth + tool.cornerRadius);
    var measureString = "EdgeMeasure ";

    zOutput.reset();
    onRapid(x, y, cycle.stock);
    onLinear(x, y, probingDepth, cycle.feedrate);
    measureString += (cycle.approach1 == "positive" ? "XPositive" : "XNegative");
    measureString += " originShift=" + xyzFormat.format(-1 * (x + approach(cycle.approach1) * startPositionOffset));
    measureString += " searchDistance=" + xyzFormat.format(cycle.probeClearance);
    writeBlock(measureString);

    forceXYZ();
    //zOutput.reset();
    onRapid(x, y, cycle.stock);
    onLinear(x, y, probingDepth, cycle.feedrate);
    
    var measureString = "EdgeMeasure ";
    measureString += (cycle.approach1 == "positive" ? "YPositive" : "YNegative");
    measureString += " originShift=" + xyzFormat.format(-1 * (y + approach(cycle.approach1) * startPositionOffset));
    measureString += " searchDistance=" + xyzFormat.format(cycle.probeClearance);
    writeBlock(measureString);
    // var isXNeagtive = (cycle.approach1 == "negative") ? true : false;
    // var isYNeagtive = (cycle.approach2 == "negative") ? true : false;
    
    // var orientation = ""
    // if (!isXNeagtive && !isYNeagtive) orientation = "BackRight";
    // if (isXNeagtive && !isYNeagtive) orientation = "BackLeft";
    // if (!isXNeagtive && isYNeagtive) orientation = "FrontRight";
    // if (isXNeagtive && isYNeagtive) orientation = "FrontLeft";
   
    // var measureString = "CornerMeasure";
    // measureString += " " + orientation;
    // measureString += " Inside";
    // measureString += " xMeasureYOffset=" + xyzFormat.format(cycle.probeClearance);
    // measureString += " yMeasureXOffset=" + xyzFormat.format(cycle.probeClearance);
    // measureString += " searchDistance=" + xyzFormat.format(cycle.probeClearance);
    // measureString += " xMeasureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    // measureString += " yMeasureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    // measureString += " forceSafeHeight"
    // measureString += " skipZMeasure";
    // measureString += " originXShift=" + xyzFormat.format(-x);
    // measureString += " originYShift=" + xyzFormat.format(-y);
    // writeBlock(measureString);
    break;
  case "probing-xy-outer-corner":
    var probingDepth = (z - cycle.depth + tool.cornerRadius);
    var touchPositionX1 = x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    var touchPositionY1 = y + approach(cycle.approach2) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    var measureString = "EdgeMeasure ";

    zOutput.reset();
    onRapid(x, y, probingDepth);
    onLinear(x, touchPositionY1, probingDepth, cycle.feedrate);
    measureString += (cycle.approach1 == "positive" ? "XPositive" : "XNegative");
    measureString += " originShift=" + xyzFormat.format(-1 * (x + approach(cycle.approach1) * startPositionOffset));
    measureString += " searchDistance=" + xyzFormat.format(cycle.probeClearance);
    writeBlock(measureString);
    forceXYZ();
    onLinear(x, touchPositionY1, probingDepth, cycle.feedrate);
    onLinear(x, y, probingDepth, cycle.feedrate);
    //forceXYZ();
    //zOutput.reset();
    onLinear(touchPositionX1, y, probingDepth, cycle.feedrate);
    onLinear(touchPositionX1, y, probingDepth, cycle.feedrate);

    var measureString = "EdgeMeasure ";
    measureString += (cycle.approach1 == "positive" ? "YPositive" : "YNegative");
    measureString += " originShift=" + xyzFormat.format(-1 * (y + approach(cycle.approach1) * startPositionOffset));
    measureString += " searchDistance=" + xyzFormat.format(cycle.probeClearance);
    writeBlock(measureString);
    forceXYZ();
    onLinear(touchPositionX1, y, probingDepth, cycle.feedrate);
    onLinear(x, y, probingDepth, cycle.feedrate);

    // var isXNeagtive = (cycle.approach1 == "negative") ? true : false;
    // var isYNeagtive = (cycle.approach2 == "negative") ? true : false;
    
    // var orientation = ""
    // if (!isXNeagtive && !isYNeagtive) orientation = "FrontLeft";
    // if (isXNeagtive && !isYNeagtive) orientation = "FrontRight";
    // if (!isXNeagtive && isYNeagtive) orientation = "BackLeft";
    // if (isXNeagtive && isYNeagtive) orientation = "BackRight";
  
    // var measureString = "CornerMeasure";
    // measureString += " " + orientation;
    // measureString += " Outside";
    // measureString += " xMeasureYOffset=" + xyzFormat.format(cycle.probeClearance);
    // measureString += " yMeasureXOffset=" + xyzFormat.format(cycle.probeClearance);
    // measureString += " searchDistance=" + xyzFormat.format(cycle.probeClearance);
    // measureString += " xMeasureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    // measureString += " yMeasureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    // measureString += " forceSafeHeight"
    // measureString += " skipZMeasure";
    // measureString += " originXShift=" + xyzFormat.format(-x);
    // measureString += " originYShift=" + xyzFormat.format(-y);
    // writeBlock(measureString);
    break;
  case "probing-x-plane-angle":
    // writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    // writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y + cycle.probeSpacing / 2) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    // writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y + cycle.probeSpacing / 2) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    // var touchPositionX1 = x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    // var touchPositionX2 = touchPositionX1;
    // writeBlock("Xvalue1 = " + touchPositionX1 + ";");
    // writeBlock("Xvalue2 = " + touchPositionX2 + ";");
    // writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    // writeBlock(gMotionModal.format(1), "x6p" + ", " + "y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    // writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y - cycle.probeSpacing / 2) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    // writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y - cycle.probeSpacing / 2) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    // writeBlock("Taxyz 2, Xvalue2, Y6p, Z6p, 1, 0, 0;");
    // writeBlock("Rotationvalue = Arctan ( ( Xvalue2 - Xvalue1 ) / " + "(" + (y + cycle.probeSpacing / 2) + "-" + (y - cycle.probeSpacing / 2) + ") );");
    // writeBlock(translate("Rotation") + " Rotationvalue, 1, 1, 1, 0, 0;");
    // writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    // writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-y-plane-angle":
    // writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    // writeBlock(gMotionModal.format(1), xOutput.format(x + cycle.probeSpacing / 2) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    // writeBlock(gMotionModal.format(0), xOutput.format(x + cycle.probeSpacing / 2) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    // var touchPositionY1 = y + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    // var touchPositionY2 = touchPositionY1;
    // writeBlock("Yvalue1 = " + touchPositionY1 + ";");
    // writeBlock("Yvalue2 = " + touchPositionY2 + ";");
    // writeBlock("Taxyz 2, X6p, Yvalue1, Z6p, 1, 0, 0;");
    // writeBlock(gMotionModal.format(1), "x6p" + ", " + "y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    // writeBlock(gMotionModal.format(1), xOutput.format(x - cycle.probeSpacing / 2) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    // writeBlock(gMotionModal.format(0), xOutput.format(x - cycle.probeSpacing / 2) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    // writeBlock("Taxyz 2, X6p, Yvalue2, Z6p, 1, 0, 0;");
    // writeBlock("Rotationvalue = Arctan ( ( Yvalue2 - Yvalue1 ) / " + "(" + (x + cycle.probeSpacing / 2) + "-" + (x - cycle.probeSpacing / 2) + ") );");
    // writeBlock(translate("Rotation") + " Rotationvalue, 1, 1, 1, 0, 0;");
    // writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    // writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  default:
    expandCyclePoint(x, y, z);
  }
  return;
}

function drilling(cycle) {
  var boreCommandString = new Array();
  var depth = xyzFormat.format(cycle.depth);
  
  boreCommandString.push("Drill");
  boreCommandString.push("depth=" + depth);
  boreCommandString.push("strokeRapidZ=" + xyzFormat.format(cycle.clearance - cycle.retract));
  boreCommandString.push("strokeCuttingZ=" + xyzFormat.format(cycle.retract - cycle.stock));
  writeBlock(boreCommandString.join(" "));
}

function chipBreaking(cycle) {
  var boreCommandString = new Array();
  var depth = xyzFormat.format(cycle.depth);
  
  boreCommandString.push("Drill");
  boreCommandString.push("depth=" + depth);
  boreCommandString.push("strokeRapidZ=" + xyzFormat.format(cycle.clearance - cycle.retract));
  boreCommandString.push("strokeCuttingZ=" + xyzFormat.format(cycle.retract - cycle.stock));
  boreCommandString.push("infeedZ=infeedZ");
  writeBlock(boreCommandString.join(" "));
}

function boreMilling(cycle) {
  if (cycle.numberOfSteps > 2) {
    error("Only 2 steps are allowed for bore-milling.");
  }

  var boreCommandString = new Array();
  var depth = xyzFormat.format(cycle.depth);
  boreCommandString.push("DrillMilling");
  boreCommandString.push("diameter=diameter");
  boreCommandString.push("depth=" + depth);
  boreCommandString.push("infeedZ=infeedZ");
  boreCommandString.push("strokeRapidZ=" + xyzFormat.format(cycle.clearance - cycle.retract));
  boreCommandString.push("strokeCuttingZ=" + xyzFormat.format(cycle.retract - cycle.stock));
  
  if (cycle.numberOfSteps == 2) {
    var xycleaning = cycle.stepover;
    var maxzdepthperstep = tool.fluteLength * 0.8;
    boreCommandString.push("finishingXY=" + xyzFormat.format(xycleaning));
    boreCommandString.push("infeedFinishingZ=" + xyzFormat.format(maxzdepthperstep));
  }
  var bottomcleaning = 0;
  // finishingZ = 1;
  writeBlock(boreCommandString.join(" "));
}

function threadMilling(cycle) {
  var threadString = new Array();
  var depth = xyzFormat.format(cycle.depth);

  threadString.push("SpecialThread");
  // threadString.push('threadName=threadName');
  threadString.push("nominalDiameter=nominalDiameter");
  threadString.push("pitch=pitch");
  threadString.push("depth=" + depth);
  threadString.push("strokeRapidZ=" + xyzFormat.format(cycle.clearance - cycle.retract));
  threadString.push("strokeCuttingZ=" + xyzFormat.format(cycle.retract - cycle.stock));
  // threadString.push("threadStandard=threadStandard");
  // threadString.push("deburring=ThreadMillingDeburring.NoDeburring");
  // threadString.push("insideOutside=ThreadMillingSide.Inside");
  threadString.push("finishing=finishing");
	if (cycle.threading == "left") {
		threadString.push("direction=ThreadMillingDirection.LeftHandThread");
	} else {
    threadString.push("direction=ThreadMillingDirection.RightHandThread");
  }
  writeBlock(threadString.join(" "));
}


function formatCycleTime(cycleTime) {
  // cycleTime = cycleTime + 0.5; // round up
  var seconds = cycleTime % 60 | 0;
  var minutes = ((cycleTime - seconds)/60 | 0) % 60;
  var hours = (cycleTime - minutes * 60 - seconds)/(60 * 60) | 0;
  if (hours > 0) {
    return subst(localize("%1h:%2m:%3s"), hours, minutes, seconds);
  } else if (minutes > 0) {
    return subst(localize("%1m:%2s"), minutes, seconds);
  } else {
    return subst(localize("%1s"), seconds);
  }
}

function dump(name, _arguments) {
  var result = getCurrentRecordId() + ": " + name + "(";
  for (var i = 0; i < _arguments.length; ++i) {
    if (i > 0) {
      result += ", ";
    }
    if (typeof _arguments[i] == "string") {
      result += "'" + _arguments[i] + "'";
    } else {
      result += _arguments[i];
    }
  }
  result += ")";
  writeln(result);
}

function onSectionEnd() {
  writeBlock("ToolCompensation Off");

  if (properties.useSequences && !isProbeOperation(currentSection)) {
    if (!properties.useExternalSequencesFiles) {
      sequenceFile.append(getRedirectionBuffer());
    }
    closeRedirection();
    spacingDepth += 1;
  }

  writeBlock("EndBlock");

  spacingDepth -= 1;

  writeBlock("endprogram " + "# " + getOperationName(currentSection));

  writeBlock(" ");
  forceAny();
}

function onClose() {

  if (properties.waitAfterOperation) {
    writeWaitProgram();
  }

  writeBlock("end");

  if (properties.useSequences && !properties.useExternalSequencesFiles) {
    writeComment(spacing);
    writeBlock(sequenceFile.toString());
  }
}
