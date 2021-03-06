configfile: "snake_eQTL_GTEx_PEER.yaml"

def get_chromosomes():
    """Function to get chromosome names from a list of chromosome file"""
    chr_list = []
    f = open(config["source_dir"] + "/chrom_lists2.txt" , 'r')
    for line in f:
        chr_num = line.split()[0]
        chr_list.append(chr_num)
        #To remove chrX and chrY from the list
        chr_list.remove("chrX")
        chr_list.remove("chrY")
    sys.stderr.write("samples: %s\n" % repr(chr_list))
    return chr_list

def read_samples():
    """Function to get sample names from specified sample file"""
    f = open(config['RPKM_dir'] + "/sample_lists.txt", "r")
    samples = []
    for line in f:
        name = line.split()[0]
        samples.append(name)
    sys.stderr.write("samples: %s\n" % repr(samples))
    return samples
    
def get_filenames():
    f = open(config['output_dir'], 'r')
    f.readline()
    d = {}
    initial = ""
    for line in f:
        col = line.split()
        chrom = col[1]
        if chrom == initial:
            d[chrom].append(line)
        elif chrom in ["chrX", "chrY", "chrMT"]:
            continue
        else:
            d[chrom] = []
            d[chrom].append(line)
        initial = chrom
    files = []
    for key in sorted(d.keys()):
        mat = d[key]
        for i in range(0, len(mat), 100): 
            files.append(key + "_subset" + str(i))
    return files


rule all:
    input:
        expand( #config['output_dir'] + "/{sample}/filtered_SNPs/{chrom}_filtered_overlappedSNPs.txt",
                #config['output_dir'] + "/{sample}/merged_SNPfiles/all_chr_filtered_overlappedSNPs.txt",
                #config['output_dir'] + "/{sample}/pca/pca_output_rotation.txt",chrom = get_chromosomes(), sample = read_samples(), files = get_filenames())
                config['output_dir'] + "/{sample}/PEER/all_chr_PEER_expr.txt",chrom = get_chromosomes(), sample = read_samples())
                #config['output_dir'] + "/{sample}/PEER/{files}_peer_expr.txt",chrom = get_chromosomes(), sample = read_samples())
                #config['output_dir'] + "/{sample}/snps_counts_comb/{files}_snps_counts_comb.txt",chrom = get_chromosomes(), sample = read_samples(), files = get_filenames())
                #config['output_dir'] + "/{sample}/output/{files}_output.txt",
                #config['output_dir'] + "/{sample}/output/all_chr_output.txt",
                #config['output_dir'] + "/{sample}/bg_genenames_onlysigp1.txt",
                #config['output_dir'] + "/{sample}/go_analysis_onlysigp1.txt"],chrom = get_chromosomes(),sample = read_samples(), files = get_filenames())
                #config['output_dir'] +  "/{sample}/dominant_snp_gene_pair.txt",chrom = get_chromosomes(),sample = read_samples(), files = get_filenames())
        

rule get_snpGenotypes:
    """get SNP genotypes for each sample"""
    input:
        exp_matrix = config['source_dir'] + "/filtered_no_peudogenes_RPKM/{sample}_RPKM_filtered_matrix.txt",
        genotypes = config["imputed_genotype"],
        snp_tab = config['snp_genotype'],
        snp_hapl = config['snp_haplotype']
        
    output:
        config['output_dir'] + "/{sample}/filtered_SNPs/{chrom}_filtered_overlappedSNPs.txt"
    shell:
        "mkdir -p {config[output_dir]}/{wildcards.sample}/filtered_SNPs ;"     
        "{config[py2]} {config[script_dir]}/get_Overlapped_SNPs_GTEx.py "                                                
        "{wildcards.chrom} {input.snp_tab} {input.snp_hapl} {input.genotypes} {input.exp_matrix} {output};"

        
rule merge_snpFiles:
    """merge genotype files"""
    input:
        expand(config['output_dir'] + "/{{sample}}/filtered_SNPs/{chrom}_filtered_overlappedSNPs.txt", chrom = get_chromosomes())
        
    output:
        config['output_dir'] + "/{sample}/merged_SNPfiles/all_chr_genotype_matrix.txt"
        
    shell:
        "{config[py2]} {config[script_dir]}/merge_genotype_files.py "                                                
        "{output} {input};"

        
rule PCA_analysis:
    """PCA analysis on the genotype matrix"""
    input:
        snp_matrix = config['output_dir'] + "/{sample}/merged_SNPfiles/all_chr_genotype_matrix.txt"
    output:
        config['output_dir'] + "/{sample}/pca/pca_output_rotation.txt"
    shell:
        "mkdir -p {config[output_dir]}/{wildcards.sample}/pca ;"     
        "Rscript --vanilla {config[script_dir]}/pca_genotypes.R {input} {output};"


rule PEER_factor:
    """Regress out covariates"""
    input:
        exp_matrix = config['source_dir'] + "/filtered_no_peudogenes_RPKM/{sample}_RPKM_filtered_matrix.txt",
        pca_matrix = config['output_dir'] + "/{sample}/pca/pca_output_rotation.txt",
        env_matrix = config['RPKM_dir'] + "/GTEx_Subject_other_phenotypes.txt"
    output:
        output = config['output_dir'] + "/{sample}/PEER/all_chr_PEER_expr.txt"

    shell:
        "mkdir -p {config[output_dir]}/{wildcards.sample}/PEER ;"     
        "Rscript --vanilla {config[script_dir]}/peer_factor.R {input.exp_matrix} {input.pca_matrix} {input.env_matrix} {output};"


rule split_jobs:
    """Create a list of file names after being split into 100 genes per job"""
    input:
        expr_matrix = config['output_dir'] + "/{sample}/PEER/all_chr_PEER_expr.txt",
        job_nums = config['output_dir'] + "/fixed_num_files.txt"
        
    output:
        output = expand([config['output_dir'] + "/{{sample}}/PEER/{files}_peer_expr.txt"],files = get_filenames())
        
    shell:
        "mkdir -p {config[output_dir]}/{wildcards.sample}/PEER ;"     
        "{config[py2]} {config[script_dir]}/split_into_files.py "
        "{input.expr_matrix} {input.job_nums} {output};"
               

rule combine_snps_counts:                                                                                                                          
    """combine SNPs that are within +/- 100kb of gene body with expression level"""                                                                 
    input:
        filtered_SNPs = config['output_dir'] + "/{sample}/merged_SNPfiles/all_chr_genotype_matrix.txt",
        counts_matrix = config['output_dir'] + "/{sample}/PEER/{files}_peer_expr.txt",
        snp_tab = config['snp_genotype'],
        snp_index = config['snp_index']
    output:                                                                                                                                              
        comb_matrix = config['output_dir'] + "/{sample}/snps_counts_comb/{files}_snps_counts_comb.txt"

    shell:        
        "mkdir -p {config[output_dir]}/{wildcards.sample}/snps_counts_comb ;"                                                        
        "{config[py2]} {config[script_dir]}/snps_counts_comb_by_chr_no_filter.py "                                                
        "{input.snp_tab} {input.snp_index} {input.filtered_SNPs} {input.counts_matrix} {output};"

        
rule matrix_multiplication:                                                                                                                            
    """perform matrix multiplication and beta approximation to obtain adjusted p-values """  
    input:			                                                                                    
        comb_matrix = config['output_dir'] + "/{sample}/snps_counts_comb/{files}_snps_counts_comb.txt"
        
    output:
        output = config['output_dir'] + "/{sample}/output/{files}_output.txt"
    shell:
         "echo HOSTNAME=$HOSTNAME >&2 ; "
         "mkdir -p {config[output_dir]}/{wildcards.sample}/output ;"                                                                                          
         "Rscript --vanilla {config[script_dir]}/beta_adjust_P_matrix_multip_corrected.R {input} {output};"

rule merge_outputfiles:
    """merge all the output subset files"""
    input:
        expand(config['output_dir'] + "/{{sample}}/output/{files}_output.txt", files = get_filenames())

    output:
        config['output_dir'] + "/{sample}/output/all_chr_output.txt"
        
    shell:
        "cat {input} > {output} ;"
        

rule summarize_output:
    """make a summary table for the results"""
    input:
        merged_output = config['output_dir'] + "/{sample}/output/all_chr_output.txt",
        gene_ref = config['output_dir'] + "/mart_gene_summary.txt",
        #expr = config['output_dir'] +  "/{sample}/PEER/all_chr_PEER_expr.txt"

    output:
        #fg_files = config['output_dir'] + "/{sample}/fg_genenames.txt",
        bg_files = config['output_dir'] + "/{sample}/bg_genenames_onlysigp1.txt",
        #summary =  config['output_dir'] + "/{sample}/new_output_summary.txt"
        
    shell:
        "Rscript --vanilla {config[script_dir]}/prepare_GO_analysis.R {input.merged_output} {input.gene_ref} {output};"

        
rule GO_analysis:
    """perform gene enrichment analysis"""
    input:
        fg_files = config['output_dir'] + "/{sample}/fg_noMHC_genenames.txt",
        bg_files = config['output_dir'] + "/{sample}/bg_genenames_onlysigp1.txt",
      
    output:
        config['output_dir'] +  "/{sample}/go_analysis_onlysigp1.txt"
        
    shell:
        "{config[py2]} {config[script_dir]}/GO_analysis/go_cat_fisher_test.py -n all {input.fg_files} {input.bg_files} > {output} ;" 
        

                
rule dominant_snp_gene_pair:
    """extract out snp-gene pair that shows dominant effects"""
    input:
        summary = config['output_dir'] + "/{sample}/new_output_summary.txt",
        f = config['output_dir'] + "/{sample}/snps_counts_comb/chr22_subset0_snps_counts_comb.txt",    
    output:
        config['output_dir'] +  "/{sample}/dominant_snp_gene_pair.txt"
        
    shell:
         "Rscript --vanilla {config[script_dir]}/extract_snp_gene_pair_comb_matrix.R {input.summary} {input.f} {wildcards.sample} {output};"
        

        
