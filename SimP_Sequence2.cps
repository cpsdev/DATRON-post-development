/**
  Copyright (C) 2012-2014 by Autodesk, Inc.
  All rights reserved.

  Minimal post processor configuration.

  $Revision: 40941 d23033c3af7c1d3a5723876fd4bd23be0cdb24b5 $
  $Date: 2016-01-16 19:30:18 $
  
  FORKID {96F3CC76-19C0-4828-BF27-6A50AED3B187}
*/

description = "Minimal Heidenhain";
vendor = "Autodesk";
vendorUrl = "http://www.autodesk.com";
legal = "Copyright (C) 2012-2014 by Autodesk, Inc.";
certificationLevel = 2;

extension = "simpl";
setCodePage("utf-8");

var spindleAxisTable = new Table(["X", "Y", "Z"], {force:true});

var radiusCompensationTable = new Table(
  [" R0", " RL", " RR"],
  {initial:RADIUS_COMPENSATION_OFF},
  "Invalid radius compensation"
);

minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(120);
allowHelicalMoves = true;
allowedCircularPlanes = (1 << PLANE_XY); // allow XY plane only


var xyzFormat = createFormat({decimals:(unit == MM ? 3 : 4), forceSign:true});
var feedFormat = createFormat({decimals:(unit == MM ? 0 : 2), scale:(unit == MM ? 1 : 10)});
var rpmFormat = createFormat({decimals:0});
var mFormat = createFormat({prefix:"M", decimals:0});
var toolFormat = createFormat({decimals:0});
var workpieceFormat = createFormat({decimals:(unit == MM ? 3 : 4), forceSign:true, trim:false});

var dimensionFormat = createFormat({decimals:(unit == MM ? 3 : 5), forceDecimal:false});
var xOutput = createVariable({prefix:" X="}, xyzFormat);
var yOutput = createVariable({prefix:" Y="}, xyzFormat);
var zOutput = createVariable({prefix:" Z="}, xyzFormat);
var iOutput = createVariable({prefix:" dX=", force : true}, feedFormat);
var jOutput = createVariable({prefix:" dY=", force : true}, feedFormat);
var kOutput = createVariable({prefix:" dZ="}, feedFormat);

var feedOutput = createVariable({prefix:"Feed="}, feedFormat);

var blockNumber = 0;

/**
  Writes the specified block.
*/
function writeBlock(block) {
  writeln(block);
}

function onOpen() {
    writeBlock("module SimPlSequence" + (programName ? (programName) : ""));
    writeBlock("");
    createToolDescriptionTable();
    writeBlock("");
    writeWorkpiece();    
    writeBlock("");
    writeBlock((unit == MM) ? "@ MeasuringSystem = \"Metric\" @" : " @ MeasuringSystem = \"Inch\" @");
    writeBlock("");
    writeBlock("sequence SimPLSequence");
    writeBlock("");
    writeBlock("using Base");
    writeBlock("");
    writeBlock("export program Main");
    writeBlock("  Spindle On"); // spindle on - clockwise
    writeBlock("  SimPLSequence");
    writeBlock("endprogram");
    writeBlock("");
    writeBlock("end");
    writeBlock("");
    writeBlock("$$$SimPLSequence");
}

/**
  Invalidates the current position and feedrate. Invoke this function to
  force X, Y, Z, and F in the following block.
*/
function invalidate() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
  feedOutput.reset();
}

function onSection() {
 //TODO 
    writeBlock("MoveToSafetyPosition");
  var retracted = true;

  writeBlock("Tool name=" + "\"" + createToolName(tool) + "\"" +
  " newRpm=" + rpmFormat.format(tool.spindleRPM) +
  " skipRestoring"
);

  setTranslation(currentSection.workOrigin);
  setRotation(currentSection.workPlane);

  invalidate();
  
  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  if (!retracted) {
    if (getCurrentPosition().z < initialPosition.z) {
      writeBlock("Rapid" + zOutput.format(initialPosition.z));
    }
  }
  writeBlock("Line" + xOutput.format(initialPosition.x) + yOutput.format(initialPosition.y) + zOutput.format(initialPosition.z));
}

function onRapid(x, y, z) {
  var xyz = xOutput.format(x) + yOutput.format(y) + zOutput.format(z);
  if (xyz) {
    writeBlock("Rapid" + xyz);
    feedOutput.reset();
  }
}

function onLinear(x, y, z, feed) {
  var xyz = xOutput.format(x) + yOutput.format(y) + zOutput.format(z);
  var f = feedOutput.format(feed);
  if(f){
      writeBlock(f);
  }
  if (xyz) {
    writeBlock("Line" + xyz);
  }
}

function onSectionEnd() {
  // full retract in machine coordinate system
  writeBlock("MoveToSafetyPosition");
  invalidate();
}

function onClose() {
  writeBlock("Spindle Off"); // stop program, spindle stop, coolant off
}

function createToolDescriptionTable() { 
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
  
  
function formatVariable(text) {
    return String(text).replace(/[^A-Za-z0-9\-_]/g, "");
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

  
function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  var f = feedOutput.format(feed);
  if(f){
      writeBlock(f);
  }
  
  // if (pendingRadiusCompensation >= 0) {
  //   error(localize("radius compensation cannot be activated/deactivated for a circular move."));
  //   return;
  // }

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
