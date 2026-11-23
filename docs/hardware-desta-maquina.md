# Hardware e ajustes desta máquina

[← Voltar ao README](../README.md)

Este projeto roda em qualquer Linux com Docker. **Nada aqui é requisito**: o que depende do hardware de um servidor específico está **comentado** nos arquivos de exemplo ([`media/docker-compose.override.example.yml`](../media/docker-compose.override.example.yml) e [`immich/docker-compose.override.example.yml`](../immich/docker-compose.override.example.yml)) ou descrito só neste documento. Ele existe para você poder **conferir o que foi feito na máquina onde isto foi validado**, e reproduzir (ou ignorar) em outra.

## A máquina de referência

| Item | Valor (conferido em 23/11/2026) |
|---|---|
| Modelo | Acer Predator PHN16-72 (notebook) |
| CPU | Intel Core i7-14700HX, 28 threads |
| GPU integrada | Intel UHD Graphics 770 (Raptor Lake-S) |
| GPU dedicada | NVIDIA GeForce RTX 4070 Laptop, 8 GB |
| Memória | 15 GB de RAM, 2 GB de swap |
| Discos | NVMe de 512 GB com o Linux e `/srv`; NVMe de 1 TB com o Windows (não usado pelo Linux) |
| Rede | Só Wi-Fi (a porta Ethernet existe, sem cabo) |
| Sistema | Linux Mint 22.3 (base Ubuntu 24.04), kernel 7.0, driver NVIDIA 595.99, Docker 29.10, Compose 5.8 |

## Divisão do trabalho entre as duas GPUs

| GPU | Trabalho | Por quê |
|---|---|---|
| Intel integrada | **Jellyfin**, em tempo real (VAAPI/Quick Sync) | Gasta pouco, esquenta pouco e já cobre os codecs do dia a dia. A decodificação por hardware cobre h264, hevc, mpeg2, vc1, vp9 e av1; a codificação em HEVC/AV1 fica desligada (padrão). |
| NVIDIA | **Immich**: aprendizado de máquina (CUDA) e transcodificação de vídeo (NVENC) | É trabalho em lote, onde a potência rende, e não disputa a GPU integrada com o Jellyfin. |

O Jellyfin só usa uma GPU por vez, e a transcodificação em tempo real é o que mais se beneficia da eficiência da integrada. Em outra máquina, use o que houver: com uma GPU só, comente o bloco da outra e ajuste a divisão.

Em notebooks com duas GPUs, os nós `/dev/dri/renderD128` e `renderD129` **trocam de dono entre boots**. Por isso o exemplo passa a pasta `/dev/dri` inteira ao container e o Jellyfin aponta para o atalho de PCI, que não muda (`/dev/dri/by-path/pci-0000:00:02.0-render`; a Intel costuma ser `00:02.0`, e você confere com `ls -l /dev/dri/by-path`).

## O que foi configurado

### 1. GPU NVIDIA nos containers (feito no host)

Instala o `nvidia-container-toolkit` pelo repositório oficial da NVIDIA e registra o runtime no Docker. **O `systemctl restart docker` reinicia todos os containers** (eles voltam sozinhos, em 1 a 2 minutos).

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
```

```bash
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
```

```bash
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
```

```bash
sudo nvidia-ctk runtime configure --runtime=docker
```

```bash
sudo systemctl restart docker
```

Teste: `docker run --rm --gpus all ubuntu nvidia-smi` deve mostrar a placa. Se o `apt-get update` falhar por causa de **outro** repositório (chave ausente, por exemplo), o `&&` impede a instalação: rode só `sudo apt-get install -y nvidia-container-toolkit`, pois a lista da NVIDIA já foi lida.

### 2. Jellyfin na GPU Intel

Bloco "GPU Intel integrada" do [exemplo de override da mídia](../media/docker-compose.override.example.yml), mais, no painel, **Reprodução → Transcodificação**: aceleração **VAAPI**, dispositivo `/dev/dri/by-path/pci-0000:00:02.0-render` e a decodificação por hardware marcada para os codecs que a GPU suporta. Conferência feita: o `vainfo` dentro do container lista a decodificação de MPEG-2, H.264, VC-1, HEVC (8 e 10 bits), VP9 e AV1; o `ffmpeg` codificou H.264 por VAAPI e decodificou HEVC sem erro.

### 3. Immich nas GPUs

- **No compose:** o `docker-compose.yml` é a cópia do oficial (com `MACHINE_LEARNING_MODEL_REVISION: v2`, que já vem na release e deixa o ML mais rápido sem reprocessar nada). As GPUs entram pelo [exemplo de override](../immich/docker-compose.override.example.yml): blocos **NVENC** (servidor) e **CUDA** (ML) descomentados nesta máquina. A alternativa para a GPU Intel é o bloco **OpenVINO**; escolha CUDA **ou** OpenVINO, não os dois.
- **Na interface (fica no banco do Immich, então volta junto com um restore do banco):** *Administração → Configurações → Transcodificação de vídeo → Aceleração por hardware = NVENC*; *Configurações → Aprendizado de máquina → Modelo CLIP =* `nllb-clip-large-siglip__v1` (multilíngue, para buscar em português). Defina o modelo **antes** de importar fotos: trocá-lo depois exige reprocessar a biblioteca. Esse modelo ocupa cerca de 4 GB em disco e, carregado, cerca de 1,8 GB de memória de vídeo só no encoder de texto; o de imagens soma a isso na indexação.
- **Verificação feita:** `docker exec immich_machine_learning nvidia-smi` e `docker exec immich_server nvidia-smi` mostram a placa; uma busca de teste rodou com o provedor `nv_tensorrt_rtx`; uma codificação H.264 de teste com NVENC terminou sem erro.
- **Sufixo da imagem:** as imagens `-cuda` e `-openvino` só são publicadas quando o ML muda, então podem ficar uma versão patch atrás da principal. É esperado.

### 4. Energia: o servidor não pode parar (feito no host, fora do repositório)

O notebook é o servidor, então ele não pode suspender com a tampa fechada nem por ociosidade. Estado conferido:

```bash
# A tampa não faz nada (arquivo /etc/systemd/logind.conf.d/lid-ignore.conf, seção [Login]):
#   HandleLidSwitch=ignore
#   HandleLidSwitchExternalPower=ignore
#   HandleLidSwitchDocked=ignore

# Nenhum caminho de suspensão ou hibernação pode ser acionado:
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

No Cinnamon: ação ao fechar a tampa = nada (na tomada e na bateria), suspensão por inatividade = nunca (`sleep-inactive-ac-timeout=0`) e ação de bateria crítica = desligar. (O UPower tem `CriticalPowerAction=HybridSleep`, que fica sem efeito com os alvos de suspensão mascarados.) A tela apaga em 30 minutos e pode ser **bloqueada** sem afetar nada (o atalho do bloqueio é `Ctrl+Alt+L`; `Super+L` abre o Looking Glass, uma ferramenta de depuração do Cinnamon). Atualizações automáticas só de segurança, sem reinício automático.

Outros pontos conferidos:

- **Limite de carga da bateria:** o Linux não expõe esse controle neste modelo (não há `charge_control_end_threshold`). O limite de 80% existe no PredatorSense, no Windows. Não foi verificado se ele foi aplicado.
- **Wi-Fi:** o servidor roda **só por Wi-Fi**, com o gerenciamento de energia do Wi-Fi **ligado** (`wifi.powersave = 3` em `/etc/NetworkManager/conf.d/default-wifi-powersave-on.conf`) e sinal fraco (cerca de −76 dBm na banda de 5 GHz). Isso pode aumentar a latência e causar quedas. **Não foi alterado.** Melhorias possíveis: usar cabo, ou criar um arquivo em `/etc/NetworkManager/conf.d/` com `[connection]` e `wifi.powersave = 2` (desligar) e reiniciar o NetworkManager.

### 5. Telemetria para avaliar calor e consumo

[`scripts/telemetria.py`](../scripts/telemetria.py) agendado no cron a cada 2 minutos (veja [Operação](operacao-backup-acesso.md#temperatura-e-consumo-telemetria)).

## Linha de base (23/11/2026, 19 amostras de 18:25 a 19:14)

Servidor na tomada, 13 containers saudáveis, biblioteca do Immich vazia, desktop aberto (navegador, IDE e outros). O período inclui os testes de ML e NVENC feitos na configuração, que explicam os picos de uso da RTX.

| Medida | Mínimo | Média | Máximo |
|---|---|---|---|
| Temperatura do pacote da CPU | 72 °C | 78 °C | 81 °C |
| Carga (1 min) | 0,5 | 1,4 | 2,5 |
| Ventoinha 1 | 2.189 rpm | 2.758 rpm | 3.000 rpm |
| RTX: temperatura | 48 °C | 51 °C | 54 °C |
| RTX: potência | 3 W | 9,6 W | 15 W |
| RTX: uso | 0% | 23% | 41% |
| NVMe do Linux (composto) | 48 °C | 52 °C | 53 °C |

Observações:

- A **RTX fica acordada** por causa do Xorg (a interface gráfica), mesmo sem trabalho de container. Isso vale para qualquer carga do Immich que se some a ela.
- A **CPU está quente para a carga baixa** que os containers geram (juntos, cerca de 3% de CPU): o desktop (navegador, IDE) pesa. Um servidor sem interface gráfica tende a ficar mais frio.
- O **contador de potência da CPU (RAPL) não é legível sem root**, então não há watts da CPU nesta tabela.
- Um sensor do NVMe de 1 TB (o do Windows) marca 87 °C de forma constante, mesmo ocioso, enquanto o valor composto desse disco está em torno de 50 °C. Parece um sensor travado, mas não foi confirmado.
- A biblioteca do Immich estava vazia: **não há carga real de indexação nem de transcodificação** nesta linha de base.

## Replicar em outra máquina

1. `make up` já cria os overrides a partir dos exemplos, **com a aceleração desativada**: tudo funciona, só na CPU.
2. Descomente nos overrides o bloco que combina com o seu hardware (e instale o `nvidia-container-toolkit` se for NVIDIA).
3. Ajuste o que é de cada máquina: o GID do grupo `render` (`getent group render`), o IP anunciado pelo Jellyfin e os nós de GPU (`ls -l /dev/dri/by-path`).
4. As configurações feitas pela interface do Immich acompanham o banco; as do Jellyfin ficam no `encoding.xml` dentro de `CONFIG_DIR` (já incluído no `make backup-config`).
