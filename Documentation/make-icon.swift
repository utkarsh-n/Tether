import AppKit
let destination=CommandLine.arguments[1]
let image=NSImage(size:NSSize(width:1024,height:1024))
image.lockFocus()
NSColor(calibratedRed:0.025,green:0.035,blue:0.085,alpha:1).setFill()
NSBezierPath(rect:NSRect(x:0,y:0,width:1024,height:1024)).fill()
let violet=NSColor(calibratedRed:0.56,green:0.43,blue:1,alpha:1)
let mint=NSColor(calibratedRed:0.5,green:1,blue:0.83,alpha:1)
let rose=NSColor(calibratedRed:1,green:0.62,blue:0.78,alpha:1)
for radius in [310.0,380.0] {
  violet.withAlphaComponent(0.5).setStroke()
  let ring=NSBezierPath(ovalIn:NSRect(x:512-radius,y:512-radius,width:radius*2,height:radius*2));ring.lineWidth=3;ring.stroke()
}
for i in 0..<12 {
  let a=Double(i)/12*Double.pi*2
  violet.withAlphaComponent(0.8).setStroke()
  let tick=NSBezierPath();tick.move(to:NSPoint(x:512+cos(a)*360,y:512+sin(a)*360));tick.line(to:NSPoint(x:512+cos(a)*384,y:512+sin(a)*384));tick.lineWidth=5;tick.stroke()
}
let orbit=NSBezierPath();orbit.move(to:NSPoint(x:250,y:355));orbit.curve(to:NSPoint(x:774,y:669),controlPoint1:NSPoint(x:380,y:725),controlPoint2:NSPoint(x:644,y:299));orbit.lineWidth=9
violet.setStroke();orbit.stroke()
for (x,y,color) in [(250.0,355.0,mint),(774.0,669.0,rose)] {
  let shadow=NSShadow();shadow.shadowColor=color.withAlphaComponent(0.5);shadow.shadowBlurRadius=50;shadow.set()
  color.setFill();NSBezierPath(ovalIn:NSRect(x:x-37,y:y-37,width:74,height:74)).fill()
  NSShadow().set()
  color.withAlphaComponent(0.6).setStroke();let ring=NSBezierPath(ovalIn:NSRect(x:x-60,y:y-60,width:120,height:120));ring.lineWidth=3;ring.stroke()
}
let star=NSBezierPath();star.move(to:NSPoint(x:512,y:582));star.curve(to:NSPoint(x:582,y:512),controlPoint1:NSPoint(x:524,y:525),controlPoint2:NSPoint(x:535,y:524));star.curve(to:NSPoint(x:512,y:442),controlPoint1:NSPoint(x:535,y:500),controlPoint2:NSPoint(x:524,y:495));star.curve(to:NSPoint(x:442,y:512),controlPoint1:NSPoint(x:500,y:495),controlPoint2:NSPoint(x:495,y:500));star.curve(to:NSPoint(x:512,y:582),controlPoint1:NSPoint(x:495,y:524),controlPoint2:NSPoint(x:500,y:525));star.close();NSColor.white.setFill();star.fill()
image.unlockFocus()
let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:destination))
