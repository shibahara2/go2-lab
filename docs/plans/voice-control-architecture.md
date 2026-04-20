# Voice Control Architecture

## Summary

- Accept voice input on a DGX Spark located in Osaka.
- Stream audio to Azure OpenAI Realtime API for speech-to-text.
- Use the transcription result on the Osaka DGX Spark to generate ROS messages.
- Relay the ROS messages through a cloud-hosted Zenoh server.
- Deliver the command stream to a Unitree Go2 in Tokyo and execute movement.

## Mermaid

```mermaid
flowchart LR
  mic["Voice Input<br/>Microphone / Operator"] --> dgx

  subgraph osaka["Osaka"]
    dgx["DGX Spark<br/>- Send audio stream<br/>- Receive transcription<br/>- Generate ROS messages"]
  end

  subgraph azure["Azure Cloud"]
    aoai["Azure OpenAI<br/>Realtime API<br/>Speech-to-text"]
  end

  subgraph relay["Cloud"]
    zenoh["Zenoh Server<br/>Message relay"]
  end

  subgraph tokyo["Tokyo"]
    go2["Unitree Go2<br/>Execute movement"]
  end

  dgx -->|"Audio stream"| aoai
  aoai -->|"Transcribed text"| dgx
  dgx -->|"ROS messages"| zenoh
  zenoh -->|"Zenoh transport"| go2
```

## Notes

- Speech recognition is handled remotely by Azure OpenAI Realtime API.
- Intent interpretation and ROS message generation stay on the Osaka DGX Spark.
- Cross-region robot command delivery is handled through the cloud Zenoh server.
