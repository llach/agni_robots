require("rttlib")
require "rttros"
tc=rtt.getTC()

metacontroller_path = rttros.find_rospack("agni_rtt_services")
package.path = metacontroller_path..'/scripts'..'/?.lua;' .. package.path
require("meta-component_common")

--wrapper interface definition (should not be changed)
iface_spec = {
   ports={},
   properties={
      { name='namespace', datatype='string', desc="namespace as prefix" },
      { name='port', datatype='int', desc="port on which FRI listens" },
      { name='fake', datatype='bool', desc="if true, SR loops cmds to joint_state" },
      { name='in_portmap', datatype='agni_rtt_services/ControlIOMap', desc="input port mapping" },
      { name='out_portmap', datatype='agni_rtt_services/ControlIOMap', desc="output port mapping" },
      { name='resources', datatype='strings', desc="joints controlled by this controller" },
      { name='controller_name', datatype='string', desc="controller name" },
      { name='controller_type', datatype='string', desc="controller type ex: position_controllers/JointTrajectoryController" },
   }
}

-- this create the interface (must be global)
iface=rttlib.create_if(iface_spec)

-- defines the configureHook of the wrapper
function configureHook()
  -- find the deployer
  local d=tc:getPeer("Deployer")
  tcName=tc:getName()

  -- import the required libraries and typekits here
  d:import("rtt_sr_bridge")
  d:import("rtt_sr_effort_limiter")
  d:import("rtt_roscomm")
  d:import("rtt_rosnode")
  d:import("rtt_rosparam")
  d:import("rtt_std_msgs")
  d:import("rtt_sensor_msgs")
  d:import("rtt_controller_manager_msgs")
  d:import("rtt_control_msgs")
  d:import("rtt_trajectory_msgs")

  --rtt.setLogLevel("Warning")

  -- retrieve the properties from the interface parameters
  namespace = iface.props.namespace:get()
  -- advertize the type of controller you set (useful for controller_manager)
  controller_type = tc:getProperty("controller_type")
  controller_type:set("position_controllers/JointPositionController")
  resources = tc:getProperty("resources")
  resources = tc:getProperty("resources")

  -- prepare ports
  port = iface.props.port:get()
  local in_portmap={}
  local out_portmap={}

  -- fake or not
  fake = iface.props.fake:get()
  if fake then
    print("SR will be started in fake mode")
    -- SR BRIDGE
    bridgename = namespace.."bridge"
    d:loadComponent(bridgename, "RTTSrFake")
    d:setActivity(bridgename, 0.001, 20, rtt.globals.ORO_SCHED_RT)
    bridge = d:getPeer(bridgename)
    d:loadService(bridgename,"rosservice")
    ns=bridge:getProperty("namespace")
    ns:set(namespace)
    --ctrltype:set("sr_mechanism_controllers/SrhMixedPositionVelocityJointController")
  else
    print("SR will be started in normal mode")
    -- SR BRIDGE
    bridgename = namespace.."bridge"
    d:loadComponent(bridgename, "RTTSrBridge")
    d:setActivity(bridgename, 0, 20, rtt.globals.ORO_SCHED_RT)
    bridge = d:getPeer(bridgename)
    d:loadService(bridgename,"rosservice")
    ns=bridge:getProperty("namespace")
    ns:set(namespace)
    ctrltype=bridge:getProperty("desired_joint_controller_type")
    --ctrltype:set("sr_mechanism_controllers/SrhMixedPositionVelocityJointController")
  end

  ctrl_joints = {'FFJ0', 'FFJ3', 'FFJ4', 'LFJ0', 'LFJ3', 'LFJ4', 'LFJ5', 'MFJ0', 'MFJ3', 'MFJ4', 'RFJ0', 'RFJ3', 'RFJ4',
'THJ1', 'THJ2', 'THJ3', 'THJ4', 'THJ5', 'WRJ1', 'WRJ2'}

  joints = {'FFJ1', 'FFJ2', 'FFJ3', 'FFJ4', 'LFJ1', 'LFJ2', 'LFJ3', 'LFJ4', 'LFJ5', 'MFJ1', 'MFJ2', 'MFJ3', 'MFJ4', 'RFJ1', 'RFJ2', 'RFJ3', 'RFJ4',
'THJ1', 'THJ2', 'THJ3', 'THJ4', 'THJ5', 'WRJ1', 'WRJ2'}

  ctrl_joint_names = bridge:getProperty("controlled_joint_names")
  ctrl_joint_names:get():resize(20)
  for i=0,19,1 do
    ctrl_joint_names[i] = namespace.."_"..ctrl_joints[i+1]
  end

  joint_names = bridge:getProperty("joint_names")
  joint_names:get():resize(24)
  for i=0,23,1 do
    joint_names[i] = namespace.."_"..joints[i+1]
  end
  
  local ros=rtt.provides("ros")

  if bridge:configure() then
    -- add bridgename to the wrapper component peers
    d:addPeer(tcName, bridgename)
    
    -- register ports for the compound controller depending on the type using generic names
    -- among CMDJNTPOS, CURJNTPOS, CMDJNT, CURJNT, LOG, ...
    register_port(in_portmap, 'CMDJNTPOS', bridgename..".JointPositionCommand")
    register_port(in_portmap, 'CMDJNTVEL', bridgename..".JointVelocityCommand")
    register_port(in_portmap, 'CMDJNT', bridgename..".DesiredJoint")

    register_port(out_portmap, 'CURJNTPOS', bridgename..".JointPosition")
    register_port(out_portmap, 'CURJNTVEL', bridgename..".JointVelocity")
    register_port(out_portmap, 'CURJNTEFF', bridgename..".JointEffort")

    -- store the mapping in the properties
    storeMapping("in_portmap",in_portmap)
    storeMapping("out_portmap",out_portmap)

    -- set the resource to match the joints
    resources:get():resize(24)
    -- fill the resource
    for i=0,23,1 do
      resources[i] = joint_names[i]
    end
    
    -- ROS in out
    -- if fake, this is an output, otherwise it is an input
    d:stream(bridgename..".joint_states",ros:topic("/"..namespace.."/joint_states"))

    if fake ~= true then
      -- EFFORT LIMITER
      efflimname = namespace.."EffLim"
      d:loadComponent(efflimname, "RTTSrGraspFatigueLimiter")
      d:setActivity(efflimname, 0, 20, rtt.globals.ORO_SCHED_RT)
      EffLim = d:getPeer(efflimname)
      ns=EffLim:getProperty("namespace")
      ns:set(namespace)
      ndof=EffLim:getProperty("nDOF"):set(20)

      fth=EffLim:getProperty("fatigue_thresholds")
      fth:get():resize(20)
      fen=EffLim:getProperty("fatigue_endurances")
      fen:get():resize(20)
      gth=EffLim:getProperty("grasp_thresholds")
      gth:get():resize(20)
      gen=EffLim:getProperty("grasp_endurances")
      gen:get():resize(20)
      hl=EffLim:getProperty("high_limits")
      hl:get():resize(20)
      ll=EffLim:getProperty("low_limits")
      ll:get():resize(20)

      -- set limits (with Big motors and Big motors on thin tendons)
      for i=0,19,1 do
        if i==18 or i==19 then  -- WRJ1-2
          fth[i] = 120.0 * 0.7
          gth[i] = 180.0 * 0.7
        else
          if i==16 or i==17 then -- THJ4-5
            fth[i] = (120.0-50.0) * 0.7
            gth[i] = (180.0-50.0) * 0.7
          else
            fth[i] = 150.0 * 0.7
            gth[i] = 220.0 * 0.7
          end
        end
        fen[i] = 500.0
        gen[i] = 50.0
        ll[i] = 0.0
        hl[i] = 1.0
      end

      if EffLim:configure() then
        -- add efflimname to the wrapper component peers
        d:addPeer(tcName, efflimname) -- ##CHANGE ME##
        -- internal connection
        d:connect(bridgename..".CtrlJointPosition", efflimname..".JointPosition", rtt.Variable("ConnPolicy"))
        d:connect(bridgename..".CtrlJointEffort", efflimname..".JointEffort", rtt.Variable("ConnPolicy"))
        d:connect(bridgename..".CtrlJointPositionCommand", efflimname..".JointPositionCommand", rtt.Variable("ConnPolicy"))
        d:connect(bridgename..".JointMaxForce", efflimname..".JointMaxForce", rtt.Variable("ConnPolicy"))
        -- ROS in out effort limiter
        d:stream(efflimname..".DebugFatigueOutput",ros:topic("/"..namespace.."/fatigue_effort_limiter/output"))
        d:stream(efflimname..".DebugFatigueAccterm",ros:topic("/"..namespace.."/fatigue_effort_limiter/accterm"))
        d:stream(efflimname..".DebugGraspOutput",ros:topic("/"..namespace.."/grasp_effort_limiter/output"))
        d:stream(efflimname..".DebugGraspAccterm",ros:topic("/"..namespace.."/grasp_effort_limiter/accterm"))
        EffLim:loadService("rosservice")
        EffLim:provides("rosservice"):connect("setFatigueEndurance", "/"..namespace.."/fatigue_effort_limiter/setEndurance", "agni_sr_effort_limiter/setEndurance")
        EffLim:provides("rosservice"):connect("setFatigueThreshold", "/"..namespace.."/fatigue_effort_limiter/setThreshold", "agni_sr_effort_limiter/setThreshold")
        EffLim:provides("rosservice"):connect("setGraspEndurance", "/"..namespace.."/grasp_effort_limiter/setEndurance", "agni_sr_effort_limiter/setEndurance")
        EffLim:provides("rosservice"):connect("setGraspThreshold", "/"..namespace.."/grasp_effort_limiter/setThreshold", "agni_sr_effort_limiter/setThreshold")
      else
        print ("failed to configure the effort_limiter, unloading the effort_limiter and bridge")
        d:unloadComponent(efflimname)
        d:unloadComponent(bridgename)
        return false
      end
    end
    print(namespace.."Wrapper is configured")
    return true
  else
    print ("failed to configure the bridge, unloading the bridge")
    d:unloadComponent(bridgename)
    return false
  end
end
