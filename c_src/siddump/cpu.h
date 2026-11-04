extern unsigned char mem[];
extern unsigned int cpucycles;
extern unsigned short pc;
extern int in_playroutine;
extern int current_play_frame;
void initcpu(unsigned short newpc, unsigned char newa, unsigned char newx, unsigned char newy);
int runcpu(void);
void record_digi_trigger(unsigned short sample_addr, unsigned short end_addr, int frame);
void print_digi_summary(void);
