#include "control_dispatch.h"
#include "studio_protocol.h"
#include "cup_commands.h"
int control_dispatch(unsigned command,const unsigned args[5]){
 count_roi roi;
 switch(command){
 case STUDIO_MODE:return cup_set_mode(args[0]);
 case STUDIO_THRESHOLD:return cup_set_threshold(args[0]);
 case STUDIO_MASK:return cup_set_mask(args[0]);
 case STUDIO_RESET:return cup_reset_count();
 case STUDIO_ROI:
  roi.ax=(int)args[0];roi.bx=(int)args[1];roi.width=(int)args[2];roi.y0=(int)args[3];roi.y1=(int)args[4];
  return cup_set_roi(roi);
 case STUDIO_PING:case STUDIO_CAPTURE:case STUDIO_STATUS:return 0;
 default:return -1;
 }
}
