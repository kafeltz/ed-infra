#!/usr/bin/env python3
"""
Script para separar logs do PostgreSQL em tempo real (blocos completos)
Separa logs de auditoria (AUDIT:) dos logs normais, mantendo entradas multiline corretas

Uso:
    python separate_logs_realtime.py <source_log> [--audit-log AUDIT] [--normal-log NORMAL]

Exemplo:
    python separate_logs_realtime.py /var/lib/postgresql/data/log/postgresql.log \
        --audit-log /var/log/postgresql/audit.log \
        --normal-log /var/log/postgresql/postgres.log
"""

import sys
import time
import gzip
import argparse
import re
from pathlib import Path
from datetime import datetime

class LogSeparator:
    def __init__(self, source_log, audit_log, normal_log,
                 max_size_mb=100, compress_old=True):
        self.source_log = Path(source_log)
        self.audit_log = Path(audit_log)
        self.normal_log = Path(normal_log)
        self.max_size_mb = max_size_mb
        self.compress_old = compress_old
        self.position = 0

        # Regex para identificar início de log PostgreSQL
        self.log_start_re = re.compile(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} [-+]\d{2}')

        # Estatísticas
        self.stats = {
            'audit_lines': 0,
            'normal_lines': 0,
            'total_lines': 0,
            'rotations': 0,
            'start_time': datetime.now()
        }

        # Criar diretórios se não existirem
        self.audit_log.parent.mkdir(parents=True, exist_ok=True)
        self.normal_log.parent.mkdir(parents=True, exist_ok=True)

        # Criar arquivos se não existirem
        self.audit_log.touch(exist_ok=True)
        self.normal_log.touch(exist_ok=True)

        print(f"📁 Configuração:")
        print(f"   Source:  {self.source_log}")
        print(f"   Audit:   {self.audit_log}")
        print(f"   Normal:  {self.normal_log}")
        print(f"   Max size: {self.max_size_mb}MB")
        print()

    def should_rotate(self, log_file):
        """Verifica se precisa rotacionar o log"""
        if not log_file.exists():
            return False
        size_mb = log_file.stat().st_size / (1024 * 1024)
        return size_mb > self.max_size_mb

    def rotate_log(self, log_file):
        """Rotaciona e opcionalmente compacta log"""
        if not log_file.exists():
            return

        timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
        rotated = log_file.with_suffix(f'.{timestamp}.log')

        # Renomear
        log_file.rename(rotated)

        # Comprimir se habilitado
        if self.compress_old:
            compressed = f'{rotated}.gz'
            with open(rotated, 'rb') as f_in:
                with gzip.open(compressed, 'wb') as f_out:
                    f_out.writelines(f_in)
            rotated.unlink()
            print(f"🔄 Log rotacionado e comprimido: {compressed}")
        else:
            print(f"🔄 Log rotacionado: {rotated}")

        # Criar novo arquivo vazio
        log_file.touch()
        self.stats['rotations'] += 1

    def process_new_lines(self):
        """Processa novas linhas do log fonte em blocos"""
        if not self.source_log.exists():
            return

        # Verificar rotação dos logs de saída
        if self.should_rotate(self.audit_log):
            self.rotate_log(self.audit_log)
        if self.should_rotate(self.normal_log):
            self.rotate_log(self.normal_log)

        try:
            with open(self.source_log, 'r', encoding='utf-8', errors='ignore') as f:
                f.seek(self.position)

                audit_blocks = []
                normal_blocks = []
                current_block = []

                for line in f:
                    self.stats['total_lines'] += 1

                    if self.log_start_re.match(line):
                        # Novo bloco
                        if current_block:
                            block_text = ''.join(current_block)
                            if 'AUDIT:' in block_text:
                                audit_blocks.append(block_text)
                                self.stats['audit_lines'] += len(current_block)
                            else:
                                normal_blocks.append(block_text)
                                self.stats['normal_lines'] += len(current_block)
                        current_block = [line]
                    else:
                        # Continuação do bloco
                        current_block.append(line)

                # Último bloco
                if current_block:
                    block_text = ''.join(current_block)
                    if 'AUDIT:' in block_text:
                        audit_blocks.append(block_text)
                        self.stats['audit_lines'] += len(current_block)
                    else:
                        normal_blocks.append(block_text)
                        self.stats['normal_lines'] += len(current_block)

                # Escrever em lote
                if audit_blocks:
                    with open(self.audit_log, 'a', encoding='utf-8') as fa:
                        fa.writelines(audit_blocks)

                if normal_blocks:
                    with open(self.normal_log, 'a', encoding='utf-8') as fn:
                        fn.writelines(normal_blocks)

                self.position = f.tell()

        except Exception as e:
            print(f"⚠️  Erro ao processar: {e}")

    def print_stats(self):
        """Imprime estatísticas de processamento"""
        uptime = datetime.now() - self.stats['start_time']
        hours = uptime.total_seconds() / 3600

        print("\n" + "="*60)
        print("📊 ESTATÍSTICAS DE PROCESSAMENTO")
        print("="*60)
        print(f"Uptime:            {uptime}")
        print(f"Total de linhas:   {self.stats['total_lines']:,}")
        print(f"Linhas de audit:   {self.stats['audit_lines']:,} ({self.stats['audit_lines']/max(1,self.stats['total_lines'])*100:.1f}%)")
        print(f"Linhas normais:    {self.stats['normal_lines']:,} ({self.stats['normal_lines']/max(1,self.stats['total_lines'])*100:.1f}%)")
        print(f"Rotações:          {self.stats['rotations']}")
        if hours > 0:
            print(f"Taxa:              {self.stats['total_lines']/hours:.0f} linhas/hora")
        print("="*60)

    def run(self, interval=1, stats_interval=300):
        """Executa monitoramento contínuo"""
        print(f"🚀 Iniciando monitoramento...")
        print(f"   Intervalo: {interval}s")
        print(f"   Stats:     a cada {stats_interval}s")
        print("   Pressione Ctrl+C para parar e ver estatísticas\n")

        last_stats = time.time()

        try:
            while True:
                self.process_new_lines()

                # Imprimir estatísticas periodicamente
                if time.time() - last_stats >= stats_interval:
                    self.print_stats()
                    last_stats = time.time()

                time.sleep(interval)

        except KeyboardInterrupt:
            print("\n\n⛔ Parando monitoramento...")
            self.print_stats()
        except Exception as e:
            print(f"\n❌ Erro fatal: {e}")
            self.print_stats()
            raise

def main():
    parser = argparse.ArgumentParser(
        description='Separa logs de auditoria PostgreSQL em tempo real (blocos)',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument('source_log', help='Arquivo de log fonte do PostgreSQL')
    parser.add_argument('--audit-log', default='audit.log', help='Arquivo de destino para logs de auditoria')
    parser.add_argument('--normal-log', default='postgres.log', help='Arquivo de destino para logs normais')
    parser.add_argument('--max-size', type=int, default=100, help='Tamanho máximo (MB) antes de rotacionar')
    parser.add_argument('--no-compress', action='store_true', help='Não comprimir logs rotacionados')
    parser.add_argument('--interval', type=float, default=1.0, help='Intervalo de verificação em segundos')
    parser.add_argument('--stats-interval', type=int, default=300, help='Intervalo para mostrar estatísticas em segundos')

    args = parser.parse_args()

    source = Path(args.source_log)
    if not source.exists():
        print(f"❌ Arquivo fonte não encontrado: {source}")
        sys.exit(1)

    separator = LogSeparator(
        source_log=args.source_log,
        audit_log=args.audit_log,
        normal_log=args.normal_log,
        max_size_mb=args.max_size,
        compress_old=not args.no_compress
    )

    separator.run(interval=args.interval, stats_interval=args.stats_interval)

if __name__ == '__main__':
    main()