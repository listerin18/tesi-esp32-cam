#include "esp_camera.h"
#include <WiFi.h>

// --- CONFIGURAZIONE WIFI ---
const char* ssid = "FRITZ!Box 7530 2,4";      
const char* password = "16667346958743877699"; 

// --- PIN MOTORI ---
const int motor1_A = 12; const int motor1_B = 13;
const int motor2_A = 14; const int motor2_B = 15;

// --- PARAMETRI LINE FOLLOWING ---
int coloreSogliaMax = 120;
bool lineFollowingAttivo = false;
int velocitaBase = 85;

// --- PIN CAMERA ESP32-CAM ---
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27
#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22

WiFiServer server(80);
unsigned long ultimoComandoTempo = 0;

// --- FUNZIONI MOTORI ---
void muoviAvanti(int v) { 
  analogWrite(motor1_A, 0); analogWrite(motor1_B, v); 
  analogWrite(motor2_A, 0); analogWrite(motor2_B, v); 
}
void muoviIndietro(int v) { 
  analogWrite(motor1_A, v); analogWrite(motor1_B, 0); 
  analogWrite(motor2_A, v); analogWrite(motor2_B, 0); 
}
void giraSinistra(int v) { 
  analogWrite(motor1_A, v); analogWrite(motor1_B, 0); 
  analogWrite(motor2_A, 0); analogWrite(motor2_B, v); 
}
void giraDestra(int v) { 
  analogWrite(motor1_A, 0); analogWrite(motor1_B, v); 
  analogWrite(motor2_A, v); analogWrite(motor2_B, 0); 
}
void fermaMotori() { 
  analogWrite(motor1_A, 0); analogWrite(motor1_B, 0); 
  analogWrite(motor2_A, 0); analogWrite(motor2_B, 0); 
}

// --- FUNZIONE PER STREAMING MJPEG ---
void handleJPGStream(WiFiClient &client){
  client.println("HTTP/1.1 200 OK");
  client.println("Content-Type: multipart/x-mixed-replace; boundary=frame");
  client.println();

  while(client.connected()){
    camera_fb_t * fb = esp_camera_fb_get();
    if(!fb) { delay(10); continue; }

    client.printf("--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %u\r\n\r\n", fb->len);
    client.write(fb->buf, fb->len);
    client.println();

    esp_camera_fb_return(fb);
    delay(50);
  }
}

// --- SETUP ---
void setup() {
  Serial.begin(115200);

  // Configura motori
  pinMode(motor1_A, OUTPUT); pinMode(motor1_B, OUTPUT);
  pinMode(motor2_A, OUTPUT); pinMode(motor2_B, OUTPUT);
  fermaMotori();

  // Configura camera
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM; config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM; config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM; config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM; config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM; config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM; config.pin_href = HREF_GPIO_NUM;
  config.pin_sscb_sda = SIOD_GPIO_NUM; config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM; config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 15000000; 
  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size = FRAMESIZE_QVGA;
  config.jpeg_quality = 30;
  config.fb_count = 1;

  if (esp_camera_init(&config) != ESP_OK) { Serial.println("Errore camera"); return; }
  sensor_t * s = esp_camera_sensor_get();
  s->set_vflip(s, 1);
  s->set_gain_ctrl(s, 0);
  s->set_exposure_ctrl(s, 0);
  s->set_agc_gain(s,15);
  s->set_aec_value(s, 350);

  // Connetti Wi-Fi
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }
  server.begin();
  Serial.println("\nWiFi Connesso!");
  Serial.print("IP: "); Serial.println(WiFi.localIP());
  Serial.println("Comandi disponibili: /LINEFOLLOW /STOP /STREAM /AVANTI /INDIETRO /SINISTRA /DESTRA");
}

// --- FUNZIONE PER ESTRAZIONE PARAMETRI HTTP ---
int estraiParametro(String req, String param){
  int p = req.indexOf(param);
  if(p==-1) return 0;
  int fine = req.indexOf("&", p);
  if(fine==-1) fine = req.indexOf(" ", p);
  return req.substring(p+param.length(), fine).toInt();
}

// --- FUNZIONE LINE FOLLOWING ---
void eseguiAnalisiLinea(camera_fb_t * fb){
  size_t rgb_len = fb->width * fb->height * 2;
  uint8_t * rgb_buf = (uint8_t *)malloc(rgb_len);
  if(!rgb_buf) return;

  if(jpg2rgb565(fb->buf, fb->len, rgb_buf, JPG_SCALE_NONE)){
    int width = fb->width;
    int height = fb->height;

    int startY = height * 0.70; 
    int endY   = height * 0.95;
    int startX = width * 0.1; 
    int endX   = width * 0.9; 

    long sommaX = 0;
    int count = 0;

    static float erroreFiltrato = 0;
    static float ultimoErrore = 0; 
    static float ultimoErroreValido = 0;

    float alpha = 0.3; 
    float Kp = 0.35; 
    float Kd = 0.4; 

    for(int y=startY;y<endY;y+=2){
      for(int x=startX;x<endX;x+=2){
        int idx = (y*width + x)*2;
        uint16_t pixel = (rgb_buf[idx+1]<<8)|rgb_buf[idx];
        uint8_t r = ((pixel>>11)&0x1F)<<3;
        uint8_t g = ((pixel>>5)&0x3F)<<2;
        uint8_t b = (pixel &0x1F)<<3;
        uint8_t grigio = (uint8_t)(0.299*r + 0.587*g +0.114*b);
        if(grigio < coloreSogliaMax){ sommaX += x; count++; }
      }
    }

    if(count>100){
      float erroreAttuale = (float)(sommaX/count) - (width/2);
      erroreFiltrato = (alpha*erroreAttuale) + ((1-alpha)*erroreFiltrato);
      ultimoErroreValido = erroreFiltrato;

      float derivata = erroreFiltrato - ultimoErrore;
      int correzione = (int)((erroreFiltrato*Kp)+(derivata*Kd));
      correzione = constrain(correzione, -60, 60);

      ultimoErrore = erroreFiltrato;

      float compensazioneSX = 1.15;
      int velSX = (int)((velocitaBase + correzione) * compensazioneSX);
      int velDX = velocitaBase - correzione;

      analogWrite(motor1_A, 0); analogWrite(motor1_B, constrain(velSX, 65, 255));
      analogWrite(motor2_A, 0); analogWrite(motor2_B, constrain(velDX, 65, 255));

      Serial.printf("ERR: %.1f | DER: %.1f | CORR: %d\n", erroreFiltrato, derivata, correzione);
    } else {
      ultimoErrore = 0;
      if(ultimoErroreValido>10) giraDestra(90);
      else if(ultimoErroreValido<-10) giraSinistra(90);
      else fermaMotori();
    }
  }
  free(rgb_buf);
}

// --- LOOP ---
void loop(){
  static unsigned long ultimoAnalisi = 0;
  WiFiClient client = server.available();

  // --- Gestione richieste web ---
  if(client){
    String req = client.readStringUntil('\r');
    client.flush();

    if(req.indexOf("/FOTO")!=-1){
      camera_fb_t * fb = esp_camera_fb_get();
      if(fb){
        client.println("HTTP/1.1 200 OK");
        client.println("Content-Type: image/jpeg");
        client.println("Access-Control-Allow-Origin: *");
        client.println();
        client.write(fb->buf, fb->len);
        esp_camera_fb_return(fb);
      }
      client.stop(); return;
    }

    if(req.indexOf("/STREAM")!=-1){ handleJPGStream(client); return; }

    if(req.indexOf("/SETCOLOR")!=-1){
      int val = estraiParametro(req,"r2=");
      if(val>0) coloreSogliaMax=val;
      client.println("HTTP/1.1 200 OK\r\n\r\nSoglia OK");
      client.stop(); return;
    }

    if(req.indexOf("/LINEFOLLOW")!=-1){ lineFollowingAttivo=true; Serial.println("MODALITA: Automatica"); }
    else if(req.indexOf("/STOP")!=-1){ lineFollowingAttivo=false; fermaMotori(); }
    else if(req.indexOf("/AVANTI")!=-1){ lineFollowingAttivo=false; muoviAvanti(180); ultimoComandoTempo=millis(); }
    else if(req.indexOf("/INDIETRO")!=-1){ lineFollowingAttivo=false; muoviIndietro(180); ultimoComandoTempo=millis(); }
    else if(req.indexOf("/SINISTRA")!=-1){ lineFollowingAttivo=false; giraSinistra(180); ultimoComandoTempo=millis(); }
    else if(req.indexOf("/DESTRA")!=-1){ lineFollowingAttivo=false; giraDestra(180); ultimoComandoTempo=millis(); }

    client.println("HTTP/1.1 200 OK\r\n\r\nOK");
    client.stop();
  }

  // --- Line Following ---
  if(lineFollowingAttivo){
    if(millis()-ultimoAnalisi>50){
      camera_fb_t * fb = esp_camera_fb_get();
      if(fb){ eseguiAnalisiLinea(fb); esp_camera_fb_return(fb); }
      ultimoAnalisi=millis();
    }
  } else {
    if(millis()-ultimoComandoTempo>800) fermaMotori();
  }
}